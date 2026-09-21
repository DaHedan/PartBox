import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 单个筛选值（含数量角标）。
class FacetValue {
  const FacetValue({required this.key, required this.label, required this.count});

  final String key;
  final String label;
  final int count;
}

/// 一个筛选列（固定列「类别」或由 params_json 数据驱动的参数列）。
class FacetGroup {
  const FacetGroup({required this.id, required this.title, required this.values});

  final String id;
  final String title;
  final List<FacetValue> values;
}

/// 已选条件 Chip。
class SelectedChip {
  const SelectedChip({required this.groupId, required this.key, required this.label});

  final String groupId;
  final String key;
  final String label;
}

/// 参数值排序：能解析为「数值 + 单位」的按数值排（100nF 在 1µF 前），
/// 解析不了的按字典序排在后面。
int compareParamValues(String a, String b) {
  final left = _parseNumberWithUnit(a);
  final right = _parseNumberWithUnit(b);
  if (left != null && right != null) {
    if (left.category == right.category) {
      final byValue = left.value.compareTo(right.value);
      if (byValue != 0) return byValue;
    } else {
      final byCategory = left.category.compareTo(right.category);
      if (byCategory != 0) return byCategory;
    }
  } else if (left != null) {
    return -1;
  } else if (right != null) {
    return 1;
  }
  return a.compareTo(b);
}

class _NumberWithUnit {
  const _NumberWithUnit(this.category, this.value);

  /// 量纲（F / H / Ω / V / W / A / Hz / % / ppm）。
  final String category;

  /// 换算到量纲基准单位后的数值。
  final double value;
}

/// 单位 →（量纲, 系数）。
const Map<String, (String, double)> _unitScales = {
  // 电容
  'pF': ('F', 1e-12),
  'nF': ('F', 1e-9),
  'uF': ('F', 1e-6),
  'mF': ('F', 1e-3),
  'F': ('F', 1),
  // 电感
  'nH': ('H', 1e-9),
  'uH': ('H', 1e-6),
  'mH': ('H', 1e-3),
  'H': ('H', 1),
  // 电阻（含 4K7 / 1M 这类简写）
  'uΩ': ('Ω', 1e-6),
  'mΩ': ('Ω', 1e-3),
  'Ω': ('Ω', 1),
  'R': ('Ω', 1),
  'kΩ': ('Ω', 1e3),
  'K': ('Ω', 1e3),
  'k': ('Ω', 1e3),
  'MΩ': ('Ω', 1e6),
  'M': ('Ω', 1e6),
  'GΩ': ('Ω', 1e9),
  // 电压 / 功率 / 电流 / 频率
  'uV': ('V', 1e-6),
  'mV': ('V', 1e-3),
  'V': ('V', 1),
  'kV': ('V', 1e3),
  'KV': ('V', 1e3),
  'uW': ('W', 1e-6),
  'mW': ('W', 1e-3),
  'W': ('W', 1),
  'kW': ('W', 1e3),
  'uA': ('A', 1e-6),
  'mA': ('A', 1e-3),
  'A': ('A', 1),
  'Hz': ('Hz', 1),
  'kHz': ('Hz', 1e3),
  'MHz': ('Hz', 1e6),
  'GHz': ('Hz', 1e9),
  // 精度与其他
  '%': ('%', 1),
  'ppm': ('ppm', 1),
};

/// 解析 `1uF` / `±10%` / `16V` / `4.7K` 这类「数值 + 单位」；解析失败返回 null。
_NumberWithUnit? _parseNumberWithUnit(String raw) {
  final text = raw
      .trim()
      .replaceAll('µ', 'u')
      .replaceAll('μ', 'u')
      .replaceAll(' ', '');
  final match = RegExp(
    r'^[±+\-]?([0-9]+(?:\.[0-9]+)?)([A-Za-zΩ%]*)$',
  ).firstMatch(text);
  if (match == null) return null;
  final number = double.tryParse(match.group(1)!);
  if (number == null) return null;
  final unit = match.group(2) ?? '';
  if (unit.isEmpty) return _NumberWithUnit('', number);
  final scale = _unitScales[unit];
  if (scale == null) return null;
  return _NumberWithUnit(scale.$1, number * scale.$2);
}

/// 多列分面筛选器（UI 规范 6.2 / 线框 04）。
///
/// 每列：列标题 + 列内搜索框 + 独立滚动的值列表；
/// 整排放在一个横向可滚动的 Row 里，列宽固定，列多时左右滑动，
/// 底部常驻横向滚动条（可拖动），并支持鼠标拖动与滚轮。
class FacetFilterBar extends StatefulWidget {
  const FacetFilterBar({
    super.key,
    required this.groups,
    required this.selection,
    required this.onToggle,
    this.height = 240,
    this.columnWidth = 200,
  });

  final List<FacetGroup> groups;
  final Map<String, Set<String>> selection;
  final void Function(String groupId, String valueKey) onToggle;
  final double height;

  /// 单列宽度（≈200dp，列多时左右滑动）。
  final double columnWidth;

  @override
  State<FacetFilterBar> createState() => _FacetFilterBarState();
}

class _FacetFilterBarState extends State<FacetFilterBar> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 滚轮横向滚动：内层纵向值列表先注册者胜（滚轮在列内仍上下滚），
  /// 未被消费时把增量用于整排左右滚动。
  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final delta = event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs()
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    if (delta == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (!_controller.hasClients) return;
      final position = _controller.position;
      final target = (position.pixels + delta)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if (target != position.pixels) _controller.jumpTo(target);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      height: widget.height,
      child: Listener(
        onPointerSignal: _handlePointerSignal,
        child: Scrollbar(
          controller: _controller,
          thumbVisibility: true,
          interactive: true,
          scrollbarOrientation: ScrollbarOrientation.bottom,
          child: SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            // 给底部横向滚动条留出位置
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < widget.groups.length; i++)
                  SizedBox(
                    width: widget.columnWidth,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(
                            color: i == widget.groups.length - 1
                                ? Colors.transparent
                                : palette.border,
                          ),
                        ),
                      ),
                      child: _FacetColumn(
                        group: widget.groups[i],
                        selected:
                            widget.selection[widget.groups[i].id] ?? const {},
                        onToggle: (key) =>
                            widget.onToggle(widget.groups[i].id, key),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FacetColumn extends StatefulWidget {
  const _FacetColumn({
    required this.group,
    required this.selected,
    required this.onToggle,
  });

  final FacetGroup group;
  final Set<String> selected;
  final void Function(String key) onToggle;

  @override
  State<_FacetColumn> createState() => _FacetColumnState();
}

class _FacetColumnState extends State<_FacetColumn> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final keyword = _search.text.trim().toLowerCase();
    final values = keyword.isEmpty
        ? widget.group.values
        : widget.group.values
              .where((v) => v.label.toLowerCase().contains(keyword))
              .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.group.title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 34,
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: '搜索',
                prefixIcon: Icon(Icons.search, size: 16, color: palette.textSub),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 28,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                filled: true,
                fillColor: palette.isDark
                    ? palette.bg
                    : const Color(0xFFF1F5F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: palette.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: palette.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: palette.primary),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: values.isEmpty
                ? Center(
                    child: Text(
                      '无',
                      style: TextStyle(fontSize: 12, color: palette.textSub),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: values.length,
                    itemBuilder: (context, index) {
                      final value = values[index];
                      final isSelected = widget.selected.contains(value.key);
                      return InkWell(
                        onTap: () => widget.onToggle(value.key),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          margin: const EdgeInsets.only(bottom: 2),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? palette.primary.withValues(alpha: 0.12)
                                : null,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  value.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: isSelected
                                        ? palette.primary
                                        : palette.text,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${value.count}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isSelected
                                      ? palette.primary
                                      : palette.textSub,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// 已选条件行：Chip 流 + 末尾"清空"。
class SelectedChipsBar extends StatelessWidget {
  const SelectedChipsBar({
    super.key,
    required this.chips,
    required this.onRemove,
    required this.onClear,
  });

  final List<SelectedChip> chips;
  final void Function(SelectedChip chip) onRemove;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (chips.isEmpty) {
      return SizedBox(
        height: 40,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '未选择筛选条件',
            style: TextStyle(fontSize: 12, color: palette.textSub),
          ),
        ),
      );
    }
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: chips.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final chip = chips[index];
                return Center(
                  child: Container(
                    height: 28,
                    padding: const EdgeInsets.only(left: 10, right: 4),
                    decoration: BoxDecoration(
                      color: palette.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: palette.primary.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          chip.label,
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.primary,
                          ),
                        ),
                        InkWell(
                          onTap: () => onRemove(chip),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: palette.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          TextButton(
            onPressed: onClear,
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 32),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              foregroundColor: palette.textSub,
            ),
            child: const Text('清空', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
