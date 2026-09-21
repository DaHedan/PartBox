import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 单个筛选值（含数量角标）。
class FacetValue {
  const FacetValue({required this.key, required this.label, required this.count});

  final String key;
  final String label;
  final int count;
}

/// 一个筛选列（类别 / 品牌 / 封装 / 动态参数）。
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

/// 多列分面筛选器（UI 规范 6.2 / 线框 04）。
///
/// 每列：列标题 + 列内搜索框 + 独立滚动的值列表；列数超出屏幕时横向滚动。
class FacetFilterBar extends StatelessWidget {
  const FacetFilterBar({
    super.key,
    required this.groups,
    required this.selection,
    required this.onToggle,
    this.height = 240,
    this.columnsPerScreen = 3,
  });

  final List<FacetGroup> groups;
  final Map<String, Set<String>> selection;
  final void Function(String groupId, String valueKey) onToggle;
  final double height;
  final int columnsPerScreen;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columnWidth = constraints.maxWidth / columnsPerScreen;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < groups.length; i++)
                  SizedBox(
                    width: columnWidth,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(
                            color: i == groups.length - 1
                                ? Colors.transparent
                                : palette.border,
                          ),
                        ),
                      ),
                      child: _FacetColumn(
                        group: groups[i],
                        selected: selection[groups[i].id] ?? const {},
                        onToggle: (key) => onToggle(groups[i].id, key),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
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
