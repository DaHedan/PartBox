/// F11.3 注入脚本。
///
/// iBOM 是 React + WebGL 的混淆构建，**class 名是构建哈希**（如
/// `router-switch-button_D9A8I`），随 EDA 版本变化，所以：
/// 所有选择器一律**文本匹配优先**，class 只做辅助特征（如 `is-select` 前缀）。
///
/// 关键实测结论（2026-09-23，智眸 V1.2 的 iBOM）：
/// - 元件清单的行是 `tr`，**第一个 td 里就是 `<input type="checkbox">`**（已焊接勾选）；
///   用它当行判据，可以避开其他表格（快捷键说明表）的行。
/// - 选中行的 `tr` 背景色为 `rgb(230, 247, 255)`（即 #e6f7ff）。
/// - 「隐藏已焊接」是 `input[name=componentsPC][value="1"]`，
///   而它**只作用于 3D 板子视图**，左列表始终全量。
/// - 阻焊颜色/焊盘喷镀由 `<meta>` 决定，已在打开前由
///   [IbomParser.prepareHtml] 改写，脚本里无需再动。
const String ibomInjectJs = r'''
(function () {
  if (window.__PARTBOX__ && window.__PARTBOX__.ready) return;

  var SELECT_BG = 'rgb(230, 247, 255)';
  var COLORS = {
    blue:   'rgb(59, 130, 246)',
    green:  'rgb(34, 197, 94)',
    yellow: 'rgb(234, 179, 8)',
    red:    'rgb(239, 68, 68)',
    gray:   'rgb(148, 163, 184)'
  };
  var LABELS = {
    gray:   '无对照数据',
    blue:   '库中完全一致',
    green:  '重要参数一致',
    yellow: '核心参数一致',
    red:    '库中无匹配'
  };
  var CYCLE = ['gray', 'blue', 'green', 'yellow', 'red'];

  var ST = {
    ready: false,
    colors: {},
    colorsByLcsc: {},
    welded: {},
    observer: null,
    timer: null,
    configTries: 0,
    configDone: false,
    radioDone: false,
    selectWatch: false,
    lastSelected: ''
  };
  window.__PARTBOX__ = ST;

  // ---------- 基础工具 ----------

  function post(payload) {
    try {
      if (window.flutter_inappwebview &&
          window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('partbox', payload);
      }
    } catch (e) { /* 桥没就绪就算了 */ }
  }

  function textOf(el) {
    if (!el) return '';
    return (el.textContent || '').replace(/\s+/g, ' ').trim();
  }

  function click(el) {
    if (!el) return false;
    try {
      ['mousedown', 'mouseup', 'click'].forEach(function (type) {
        el.dispatchEvent(new MouseEvent(type, {
          bubbles: true, cancelable: true, view: window
        }));
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  // 按文本找元素：优先完全相等，其次「包含且自身文本不长」（避免命中大容器）。
  function byText(tags, texts, maxLen) {
    var loose = null;
    for (var t = 0; t < tags.length; t++) {
      var all = document.querySelectorAll(tags[t]);
      for (var i = 0; i < all.length; i++) {
        var text = textOf(all[i]);
        if (!text) continue;
        for (var j = 0; j < texts.length; j++) {
          if (text === texts[j]) return all[i];
          if (!loose && text.length <= (maxLen || 40) &&
              text.indexOf(texts[j]) >= 0) {
            loose = all[i];
          }
        }
      }
    }
    return loose;
  }

  // ---------- 元件清单的行 ----------

  // 元件行的判据：**直接子 td** 里就带 input[type=checkbox]。
  // 表头那行是 th（里面是全选勾选框），不算元件行，必须排掉。
  function checkboxOf(tr) {
    var tds = tr.children;
    for (var j = 0; j < tds.length; j++) {
      if (tds[j].tagName !== 'TD') continue;
      var kids = tds[j].children;
      for (var k = 0; k < kids.length; k++) {
        if (kids[k].tagName === 'INPUT' && kids[k].type === 'checkbox') {
          return kids[k];
        }
      }
    }
    return null;
  }

  function listRows() {
    var rows = document.querySelectorAll('tbody tr');
    var out = [];
    for (var i = 0; i < rows.length; i++) {
      if (checkboxOf(rows[i])) out.push(rows[i]);
    }
    return out;
  }

  var DES_RE = /^[A-Za-z]{1,4}\d{1,4}$/;

  // 位号在第 2 个 td（顶层）/ 第 3 个 td（底层）里；跳过第 1 个（勾选框列）。
  // 只看**第一个能解析出位号的格子**，两种渲染都要兼容：
  // - 位号不聚合：这一格是**纯文本** `<td>C1</td>`，根本没有 span；
  // - 位号聚合：同一格里有多个位号，各自是 `<span>`（中间用「、」分隔），
  //   这一格的颗数就是点「完成」该扣的数量。
  // 不跨格收集，免得把值/封装里长得像位号的串也算进来、重复扣库存。
  function designatorsOf(tr) {
    var tds = tr.children;
    for (var i = 1; i < Math.min(tds.length, 4); i++) {
      var out = [];
      var spans = tds[i].querySelectorAll('span');
      for (var j = 0; j < spans.length; j++) {
        var text = textOf(spans[j]);
        if (DES_RE.test(text)) out.push(text.toUpperCase());
      }
      if (out.length > 0) return out;
      var whole = textOf(tds[i]);
      if (DES_RE.test(whole)) return [whole.toUpperCase()];
    }
    return [];
  }

  function designatorOf(tr) {
    var list = designatorsOf(tr);
    return list.length > 0 ? list[0] : '';
  }

  // 列表是否处于「位号聚合」态。不看 class（按钮根本没 class），
  // 而是看有没有某一格里塞了多个位号 —— 行为判据更抗版本漂移。
  function isAggregated() {
    var rows = listRows();
    for (var i = 0; i < rows.length; i++) {
      if (designatorsOf(rows[i]).length > 1) return true;
    }
    return false;
  }

  function rowOf(designator) {
    var rows = listRows();
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].getAttribute('data-partbox-des') === designator) {
        return rows[i];
      }
    }
    for (var k = 0; k < rows.length; k++) {
      if (designatorOf(rows[k]) === designator) {
        rows[k].setAttribute('data-partbox-des', designator);
        return rows[k];
      }
    }
    return null;
  }

  function selectedRow() {
    var rows = listRows();
    for (var i = 0; i < rows.length; i++) {
      if (getComputedStyle(rows[i]).backgroundColor === SELECT_BG) {
        return rows[i];
      }
    }
    return null;
  }

  function selectedDesignator() {
    var row = selectedRow();
    if (!row) return '';
    var des = row.getAttribute('data-partbox-des') || designatorOf(row);
    return des || '';
  }

  // ---------- 四色标记 ----------

  // 颜色：优先按位号查；聚合模式下位号是一串，退回按行里的 C 编号查（PRD 11.5）。
  function statusOf(tr, des) {
    if (des && ST.colors[des]) return ST.colors[des];
    var text = textOf(tr);
    var m = /C\d{3,}/g;
    var hit = null;
    while ((hit = m.exec(text)) !== null) {
      var status = ST.colorsByLcsc[hit[0].toUpperCase()];
      if (status) return status;
    }
    return des ? (ST.colors[des] || 'gray') : 'gray';
  }

  // 幂等：只在需要变更时写 DOM，否则 MutationObserver 会自激。
  function markRow(tr) {
    var des = tr.getAttribute('data-partbox-des') || designatorOf(tr);
    if (!des) return;
    if (tr.getAttribute('data-partbox-des') !== des) {
      tr.setAttribute('data-partbox-des', des);
    }
    var status = statusOf(tr, des);
    var welded = !!ST.welded[des];

    var dot = tr.querySelector('.partbox-dot');
    if (!dot) {
      var firstTd = tr.children[0];
      if (!firstTd) return;
      if (getComputedStyle(firstTd).position === 'static') {
        firstTd.style.position = 'relative';
      }
      firstTd.style.paddingLeft = '18px';
      dot = document.createElement('span');
      dot.className = 'partbox-dot';
      dot.style.cssText = 'position:absolute;left:3px;top:50%;' +
        'transform:translateY(-50%);width:11px;height:11px;' +
        'border-radius:50%;cursor:pointer;z-index:6;' +
        'box-shadow:0 0 0 1px rgba(0,0,0,.3)';
      dot.addEventListener('click', function (ev) {
        ev.stopPropagation();
        ev.preventDefault();
        cycleColor(des);
      });
      dot.addEventListener('mousedown', function (ev) {
        ev.stopPropagation();
      });
      firstTd.appendChild(dot);
    }
    var rgb = COLORS[status] || COLORS.gray;
    if (dot.style.backgroundColor !== rgb) dot.style.backgroundColor = rgb;
    var title = 'PartBox：' + (LABELS[status] || status) + '（点击切换标记）';
    if (dot.title !== title) dot.title = title;

    var opacity = welded ? '0.55' : '';
    if (tr.style.opacity !== opacity) tr.style.opacity = opacity;
  }

  function refresh() {
    // 任何一步出错都不能影响 iBOM 自身（PRD 11.8 静默降级），
    // 但要把原因报给 Dart，免得排查时全是哑巴。
    try {
      autoConfig();
      var rows = listRows();
      for (var i = 0; i < rows.length; i++) markRow(rows[i]);
    } catch (e) {
      post({ type: 'error', message: '标记失败：' + e });
    }
  }

  function schedule() {
    if (ST.timer) return;
    ST.timer = setTimeout(function () {
      ST.timer = null;
      refresh();
    }, 120);
  }

  // 虚拟滚动会边滚边增删行，靠 MutationObserver 持续补标（PRD 11.5）。
  function observe() {
    if (ST.observer) return;
    ST.observer = new MutationObserver(function () { schedule(); });
    ST.observer.observe(document.body, { childList: true, subtree: true });
  }

  function cycleColor(des) {
    var now = ST.colors[des] || 'gray';
    var next = CYCLE[(CYCLE.indexOf(now) + 1) % CYCLE.length];
    ST.colors[des] = next;
    refresh();
    post({ type: 'color', designator: des, status: next });
  }

  // ---------- 已焊接勾选 ----------

  function setWelded(des, welded) {
    var row = rowOf(des);
    if (!row) return false;
    var box = checkboxOf(row);
    if (!box) return false;
    if (!!box.checked !== welded) click(box);
    return true;
  }

  // 选中下一个未焊接的行（点行即可，3D 高亮是 iBOM 原生能力）。
  function selectNextAfter(des) {
    var rows = listRows();
    var start = -1;
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].getAttribute('data-partbox-des') === des) { start = i; break; }
    }
    var order = [];
    for (var k = start + 1; k < rows.length; k++) order.push(rows[k]);
    for (var m = 0; m <= start && start >= 0; m++) order.push(rows[m]);
    if (start < 0) order = rows;
    for (var n = 0; n < order.length; n++) {
      var rowDes = order[n].getAttribute('data-partbox-des') || '';
      if (rowDes && !ST.welded[rowDes]) {
        ST.lastSelected = rowDes;
        click(order[n]);
        return rowDes;
      }
    }
    return '';
  }

  function selectDesignator(des) {
    var row = rowOf(des);
    if (!row) return false;
    ST.lastSelected = des;
    click(row);
    return true;
  }

  // 用户自己点行选中时也要通知 Dart（底部要显示这一颗的库位与余量）。
  // 用捕获阶段，既抢在 React 前面拿到事件，又不停 propagation（iBOM 照常选中）。
  function bindSelectionWatch() {
    if (ST.selectWatch) return;
    ST.selectWatch = true;
    document.addEventListener('click', function (ev) {
      var node = ev.target;
      while (node && node !== document.body) {
        if (node.tagName === 'TR' && checkboxOf(node)) {
          var des = node.getAttribute('data-partbox-des') || designatorOf(node);
          if (des && des !== ST.lastSelected) {
            ST.lastSelected = des;
            post({ type: 'select', designator: des });
          }
          return;
        }
        node = node.parentNode;
      }
    }, true);
  }

  // ---------- 底部双按钮 ----------

  function injectActions() {
    if (document.getElementById('partbox-actions')) return;
    var bar = document.createElement('div');
    bar.id = 'partbox-actions';
    bar.style.cssText = 'position:fixed;left:50%;bottom:16px;' +
      'transform:translateX(-50%);display:flex;gap:16px;' +
      'z-index:2147483000;font-family:"Segoe UI","Microsoft YaHei UI",' +
      '"Microsoft YaHei",sans-serif';

    function button(id, label, bg, hint) {
      var b = document.createElement('button');
      b.id = id;
      b.type = 'button';
      b.textContent = label;
      b.title = hint;
      b.style.cssText = 'min-width:150px;height:56px;padding:0 26px;' +
        'border:0;border-radius:12px;color:#fff;font-size:19px;' +
        'font-weight:700;cursor:pointer;box-shadow:0 6px 18px rgba(0,0,0,.35);' +
        'background:' + bg;
      return b;
    }

    var loss = button('partbox-loss', '丢失', '#dc2626',
      '库存 −1，记「焊接丢失」（Ctrl+Backspace）');
    var weld = button('partbox-weld', '完成', '#16a34a',
      '库存 −1，记「焊接完成」并勾选已焊接（Ctrl+Enter）');
    bar.appendChild(loss);
    bar.appendChild(weld);
    document.body.appendChild(bar);

    loss.addEventListener('click', function (ev) {
      ev.stopPropagation();
      fire(true);
    });
    weld.addEventListener('click', function (ev) {
      ev.stopPropagation();
      fire(false);
    });
  }

  function fire(loss) {
    // 位号聚合时一行是多颗同料元件，要把整行的位号都报给 Dart：
    // 「完成」扣整组，「丢失」只扣一颗（由 Dart 侧决定）。
    var row = selectedRow();
    var list = row ? designatorsOf(row) : [];
    if (list.length === 0) {
      var single = selectedDesignator();
      if (single) list = [single];
    }
    post({
      type: 'weld',
      designator: list.length > 0 ? list[0] : '',
      designators: list,
      loss: !!loss
    });
  }

  // Windows 端键盘快捷键（焦点在网页里，所以由脚本接管）。
  function bindKeys() {
    document.addEventListener('keydown', function (ev) {
      if (!ev.ctrlKey) return;
      if (ev.key === 'Enter') {
        ev.preventDefault();
        fire(false);
      } else if (ev.key === 'Backspace') {
        ev.preventDefault();
        fire(true);
      }
    }, true);
  }

  // ---------- 打开自动配置（PRD 11.4） ----------

  function autoConfig() {
    // 1) 位号不聚合：它是导航里的一个 <button>（**没有 class**，只能按文本找），
    //    而且没有可判定的选中态，所以用「列表是否聚合」当判据，聚合才点。
    //    行还没渲染完时点了也没用，靠 refresh 里的重试兜住。
    if (!ST.configDone && ST.configTries < 5) {
      ST.configTries++;
      if (!isAggregated()) {
        ST.configDone = true;
      } else {
        var uncombined = byText(
          ['button', 'div', 'span', 'a', 'li'],
          ['位号不聚合', 'Uncombined Designators', 'Uncombined'],
          32
        );
        if (uncombined) click(uncombined);
      }
    }

    // 2) 隐藏已焊接：radio name=componentsPC，value=1。
    //    只影响 3D 板子视图，左列表始终全量（PRD 11.4 实测）；
    //    用「隐藏」而不是「仅显示」，是因为选中时只有元件模型会高亮，
    //    把焊过的藏起来才看得清剩下的。
    if (ST.radioDone) return;
    var label = byText(['label', 'span'],
      ['隐藏已焊接', 'Hide Soldered'], 32);
    var radio = null;
    if (label && label.htmlFor) {
      radio = document.getElementById(label.htmlFor);
    }
    if (!radio) {
      radio = document.querySelector('input[name=componentsPC][value="1"]') ||
        document.querySelector('#hide');
    }
    if (radio && !radio.checked) click(radio);
    if (radio && radio.checked) ST.radioDone = true;

    // 3) 阻焊绿 + 焊盘喷锡银：由打开前的 <meta> 改写完成，这里不用管。
  }

  // ---------- 等待 iBOM 渲染完成 ----------

  function waitForRows() {
    var started = Date.now();
    (function tick() {
      var rows = listRows();
      if (rows.length > 0) {
        autoConfig();
        refresh();
        observe();
        injectActions();
        bindKeys();
        bindSelectionWatch();
        ST.ready = true;
        post({ type: 'ready', rows: rows.length });
        return;
      }
      if (Date.now() - started > 30000) {
        post({ type: 'error', message: '没等到元件清单渲染出来' });
        return;
      }
      setTimeout(tick, 250);
    })();
  }

  // ---------- 给 Dart 调用的接口 ----------

  window.PartBox = {
    applyState: function (payload) {
      payload = payload || {};
      ST.colors = payload.colors || {};
      ST.colorsByLcsc = payload.colorsByLcsc || {};
      var welded = payload.welded || [];
      var map = {};
      for (var i = 0; i < welded.length; i++) map[welded[i]] = true;
      ST.welded = map;

      // 回放勾选状态（iBOM 自己不持久化，重开要靠这里注入）
      for (var j = 0; j < welded.length; j++) setWelded(welded[j], true);

      refresh();
      if (payload.selectAfter) {
        var next = selectNextAfter(payload.selectAfter);
        if (next) post({ type: 'select', designator: next });
      } else if (payload.select) {
        if (selectDesignator(payload.select)) {
          post({ type: 'select', designator: payload.select });
        }
      }
      return true;
    },
    refresh: function () { refresh(); return true; },
    // 清空已焊接：把列表里的勾全部取消（iBOM 不存进度，真正清的是 Dart 侧）。
    clearWelded: function () {
      ST.welded = {};
      var rows = listRows();
      for (var i = 0; i < rows.length; i++) {
        var box = checkboxOf(rows[i]);
        if (box && box.checked) click(box);
      }
      refresh();
      return true;
    },
    selected: function () { return selectedDesignator(); },
    rowCount: function () { return listRows().length; },
    weldedCount: function () {
      var n = 0;
      for (var k in ST.welded) if (ST.welded[k]) n++;
      return n;
    },
    // 结构漂移时用来体检（也可在控制台里手动跑）。
    stats: function () {
      var rows = listRows();
      var withDot = 0;
      var withDes = 0;
      for (var i = 0; i < rows.length; i++) {
        if (rows[i].querySelector('.partbox-dot')) withDot++;
        if (rows[i].getAttribute('data-partbox-des')) withDes++;
      }
      return {
        rows: rows.length,
        withDot: withDot,
        withDes: withDes,
        aggregated: isAggregated(),
        ready: ST.ready,
        configDone: ST.configDone,
        configTries: ST.configTries,
        colors: Object.keys(ST.colors).length,
        welded: Object.keys(ST.welded).length
      };
    }
  };

  waitForRows();
})();
''';
