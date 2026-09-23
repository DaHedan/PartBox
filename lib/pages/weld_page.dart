import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../data/models.dart';
import '../data/repositories/bom_repository.dart';
import '../data/repositories/weld_repository.dart';
import '../data/seed_data.dart';
import '../data/weld/ibom_import.dart';
import '../data/weld/ibom_js.dart';
import '../data/weld/weld_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/dialogs.dart';

/// F11 焊接辅助：内置 WebView 加载嘉立创 iBOM（单文件 HTML），
/// 左清单右板图 + 底部【掉了】【焊好了】联动库存。
///
/// 强制桌面 UA + 视口宽度，Android / Windows 都是电脑端画面（PRD 11.3）。
class WeldPage extends StatefulWidget {
  const WeldPage({super.key, required this.projectId, required this.title});

  final int projectId;
  final String title;

  @override
  State<WeldPage> createState() => _WeldPageState();
}

class _WeldPageState extends State<WeldPage> {
  /// 桌面 Chrome UA：让 iBOM 走电脑端布局。
  static const String _desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  InAppWebViewController? _controller;
  List<BomItem> _items = const [];

  int _welded = 0;
  int _total = 0;
  String _current = '';
  String? _error;
  bool _busy = false;

  /// 当前选中元件在库里的物料（null = 库里没匹配到）。
  MaterialItem? _currentMaterial;

  /// 是否已经查过（用来区分「未匹配」和「还没查」）。
  bool _infoLoaded = false;

  /// iBOM 的 `file://` 地址（加载完才知道，空 = 还没就绪）。
  String _htmlUrl = '';

  @override
  void initState() {
    super.initState();
    _lockLandscape();
    _load();
  }

  /// 手机端 iBOM 是「左清单右板图」的桌面布局，竖屏太挤，进页面直接转横屏。
  /// 电脑端没有重力感应，不用管。
  Future<void> _lockLandscape() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  /// 退出时放开限制，恢复跟随系统。
  Future<void> _restoreOrientation() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  Future<void> _load() async {
    try {
      final project = await BomRepository.byId(widget.projectId);
      if (project == null) {
        setState(() => _error = '工程不存在，可能已被删除');
        return;
      }
      final items = await BomRepository.items(widget.projectId);
      final welded = await WeldRepository.weldedCount(widget.projectId);
      final path = await IbomImportService.htmlPathOf(project);
      if (!File(path).existsSync()) {
        setState(() => _error = '找不到 iBOM 文件，请重新导入');
        return;
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _total = items.length;
        _welded = welded;
        _htmlUrl = Uri.file(path).toString();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '加载失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: const TextStyle(fontSize: 16)),
            Text(
              _total == 0
                  ? '加载中…'
                  : '已焊 $_welded / $_total'
                        '${_current.isEmpty ? '' : ' · 当前 $_current'}',
              style: TextStyle(fontSize: 11, color: palette.textSub),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '清空已焊接',
            onPressed: _busy || _welded == 0 ? null : _clearWelded,
            icon: const Icon(Icons.restart_alt),
          ),
          IconButton(
            tooltip: '重新同步四色标记与焊接进度',
            onPressed: _busy ? null : () => _pushState(),
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.textSub),
                ),
              ),
            )
          : _htmlUrl.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(child: _webView()),
                _selectionBar(palette),
              ],
            ),
    );
  }

  Widget _webView() {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(_htmlUrl)),
      initialSettings: InAppWebViewSettings(
        userAgent: _desktopUserAgent,
        javaScriptEnabled: true,
        // 本地单文件 HTML：允许 file:// 读取自身资源
        allowFileAccess: true,
        allowFileAccessFromFileURLs: true,
        allowUniversalAccessFromFileURLs: true,
        useWideViewPort: true,
        loadWithOverviewMode: false,
        supportZoom: true,
        builtInZoomControls: true,
        displayZoomControls: false,
        preferredContentMode: UserPreferredContentMode.DESKTOP,
      ),
      onWebViewCreated: (controller) {
        _controller = controller;
        controller.addJavaScriptHandler(
          handlerName: 'partbox',
          callback: _onJsMessage,
        );
      },
      onLoadStop: (controller, url) async {
        await controller.evaluateJavascript(source: ibomInjectJs);
      },
    );
  }

  /// 底部栏：当前选中元件在库里放在哪、还剩多少。
  ///
  /// 不写四色图例 —— 色点的含义在 F10 对照页里已经交代过，
  /// 焊的时候更有用的是「这颗料在哪个仓库、还有几颗」。
  Widget _selectionBar(AppPalette palette) {
    final selected = _current.isNotEmpty;
    final material = _currentMaterial;

    final String text;
    if (!selected) {
      text = '在左侧列表里点一个元件，这里显示它的库位与余量';
    } else if (!_infoLoaded) {
      text = '$_current · 正在查库存…';
    } else if (material == null) {
      text = '$_current · 库中未匹配到物料，只记焊接进度';
    } else {
      final location = (material.locationName ?? '').isEmpty
          ? kUnassignedLocationName
          : material.locationName!;
      text =
          '$_current · 位置：$location · 余量 ${formatQty(material.qtyRemaining)}';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      color: palette.card,
      child: Row(
        children: [
          if (selected) ...[
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _statusColor(_current, palette),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    color: palette.text,
                    fontFeatures: kTabularFigures,
                  ),
                ),
                if (selected && material != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${material.title}'
                      '${(material.lcscCode ?? '').isEmpty ? '' : ' · ${material.lcscCode}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: palette.textSub),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 查当前选中元件在库里的物料（没匹配到就是 null）。
  Future<void> _loadSelected(String designator) async {
    if (!mounted) return;
    setState(() {
      _current = designator;
      _infoLoaded = false;
    });
    if (designator.isEmpty) {
      setState(() {
        _currentMaterial = null;
        _infoLoaded = true;
      });
      return;
    }
    final item = _itemOf(designator);
    final material = item == null
        ? null
        : await WeldService.resolveMaterial(item);
    // 查的过程中用户可能已经点到别的元件了
    if (!mounted || _current != designator) return;
    setState(() {
      _currentMaterial = material;
      _infoLoaded = true;
    });
  }

  Color _statusColor(String designator, AppPalette palette) {
    final item = _itemOf(designator);
    switch (item?.matchStatus) {
      case MatchStatus.blue:
        return palette.primary;
      case MatchStatus.green:
        return palette.success;
      case MatchStatus.yellow:
        return const Color(0xFFEAB308);
      case MatchStatus.red:
        return palette.danger;
      default:
        return palette.textSub;
    }
  }

  // ---------- JS ↔ Dart ----------

  /// 把四色标记与焊接进度推给页面（重开 iBOM 时靠这里回放勾选）。
  ///
  /// [selectFirstUnwelded]：回放勾选时会顺带把 iBOM 的选中行带到最后勾的那行，
  /// 所以打开时显式把选中落回第一个未焊接的位号。
  Future<void> _pushState({
    String? selectAfter,
    bool selectFirstUnwelded = false,
  }) async {
    final controller = _controller;
    if (controller == null) return;
    final byDesignator = <String, String>{};
    final byLcsc = <String, String>{};
    for (final item in _items) {
      final status = item.matchStatus;
      if (status == null || status.isEmpty) continue;
      if (item.designator.isNotEmpty) byDesignator[item.designator] = status;
      final code = item.lcscCode.trim().toUpperCase();
      if (code.isNotEmpty) byLcsc[code] = status;
    }
    final welded = await WeldRepository.weldedDesignators(widget.projectId);
    final payload = jsonEncode({
      'colors': byDesignator,
      'colorsByLcsc': byLcsc,
      'welded': welded,
      'selectAfter': ?selectAfter,
      'select': ?(selectFirstUnwelded ? _firstUnwelded(welded) : null),
    });
    await controller.evaluateJavascript(
      source: 'window.PartBox && window.PartBox.applyState($payload);',
    );
  }

  /// 第一个还没焊接的位号。
  String? _firstUnwelded(List<String> welded) {
    final done = welded.toSet();
    for (final item in _items) {
      if (item.designator.isNotEmpty && !done.contains(item.designator)) {
        return item.designator;
      }
    }
    return null;
  }

  Future<void> _onJsMessage(List<dynamic> args) async {
    final raw = args.isEmpty ? null : args.first;
    if (raw is! Map) return;
    final message = raw.cast<Object?, Object?>();
    final type = message['type']?.toString() ?? '';
    switch (type) {
      case 'ready':
        await _pushState(selectFirstUnwelded: true);
      case 'select':
        await _loadSelected(message['designator']?.toString() ?? '');
      case 'weld':
        await _onWeld(_weldDesignators(message), message['loss'] == true);
      case 'error':
        if (!mounted) return;
        showToast(context, message['message']?.toString() ?? 'iBOM 注入失败');
    }
  }

  /// 清空已焊接（要确认）。
  ///
  /// 只取消勾选：库存流水是真实出入库动作，不随勾选一起回滚（PRD 11.7）。
  Future<void> _clearWelded() async {
    final sure = await showConfirmDialog(
      context,
      title: '清空已焊接',
      message: '将取消本工程全部已焊接勾选，从头开始焊。\n'
          '已产生的库存流水不会回滚；要退料，去物料详情页改「消耗量」。',
      confirmText: '清空',
      danger: true,
    );
    if (sure != true) return;

    await WeldRepository.clearWelded(widget.projectId);
    final controller = _controller;
    if (controller != null) {
      await controller.evaluateJavascript(
        source: 'window.PartBox && window.PartBox.clearWelded();',
      );
    }
    if (!mounted) return;
    setState(() => _welded = 0);
    await _pushState(selectFirstUnwelded: true);
    if (mounted) showToast(context, '已清空已焊接');
  }

  /// JS 报上来的「这一行的位号」：聚合时是整组，不聚合时只有一个。
  List<String> _weldDesignators(Map<Object?, Object?> message) {
    final raw = message['designators'];
    if (raw is List) {
      final list = [
        for (final one in raw)
          if (one?.toString().trim().isNotEmpty ?? false)
            one.toString().trim(),
      ];
      if (list.isNotEmpty) return list;
    }
    final single = message['designator']?.toString().trim() ?? '';
    return single.isEmpty ? const [] : [single];
  }

  /// 「丢失」/「完成」：库存 −1 + 写流水 + 记进度。
  ///
  /// 位号聚合时这一行是多颗同料元件：**完成**要按整组扣（每颗一条流水、各自勾选），
  /// **丢失**仍然只扣 1 颗 —— 丢的是手里的元件，不是这一组。
  Future<void> _onWeld(List<String> designators, bool loss) async {
    if (designators.isEmpty) {
      showToast(context, '先在左侧列表里选中一个元件');
      return;
    }
    if (_busy) return;
    _busy = true;
    try {
      final targets = loss ? designators.take(1).toList() : designators;
      var matched = 0;
      double? remaining;
      for (final designator in targets) {
        final item = _itemOf(designator);
        final material = item == null
            ? null
            : await WeldService.resolveMaterial(item);
        final outcome = await WeldService.record(
          bomProjectId: widget.projectId,
          designator: designator,
          bomItemId: item?.id,
          materialId: material?.id,
          loss: loss,
        );
        if (outcome.matched) {
          matched++;
          remaining = outcome.remainingAfter;
        }
      }

      // 焊好了 → 勾选已焊接并自动选中下一个未焊接（PRD 11.6）。
      // selectAfter 用这一组的第一个位号：iBOM 的 data-partbox-des 就是它，
      // JS 靠它定位当前行再往后找。
      await _pushState(selectAfter: loss ? null : designators.first);
      final welded = await WeldRepository.weldedCount(widget.projectId);

      if (!mounted) return;
      setState(() => _welded = welded);

      // 余量变了，底部栏跟着刷新
      // （若 JS 已把选中移到下一颗，这里的调用会被竞态守卫跳过）
      await _loadSelected(_current);
      if (!mounted) return;

      final label = designators.length > 1
          ? '${designators.first}…${designators.last}（${targets.length} 颗）'
          : designators.first;
      if (matched == 0) {
        showToast(context, '未匹配库存，仅记焊接进度（$label）');
      } else {
        final tail = remaining == null ? '' : '，余量 ${formatQty(remaining)}';
        showToast(
          context,
          loss
              ? '$label 丢失 · 库存 −1$tail'
              : '$label 完成 · 库存 −${targets.length}$tail',
        );
      }
    } catch (error) {
      if (mounted) showToast(context, '操作失败：$error');
    } finally {
      _busy = false;
    }
  }

  /// 位号 → 工程里的比对条目。
  BomItem? _itemOf(String designator) {
    for (final item in _items) {
      if (item.designator.toUpperCase() == designator.toUpperCase()) {
        return item;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _restoreOrientation();
    _controller?.dispose();
    super.dispose();
  }
}
