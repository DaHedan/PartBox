import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../data/repositories/material_repository.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/material_card.dart';
import 'material_detail_page.dart';

/// P9 全局搜索页。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  Future<List<MaterialItem>> _future = Future.value(const []);
  String _keyword = '';
  int _revision = -1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _run(String value) {
    _keyword = value.trim();
    setState(() {
      _future = _keyword.isEmpty
          ? Future.value(const <MaterialItem>[])
          : MaterialRepository.search(_keyword);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final revision = context.watch<AppState>().revision;
    if (revision != _revision) {
      _revision = revision;
      if (_keyword.isNotEmpty) {
        _future = MaterialRepository.search(_keyword);
      }
    }
    final appState = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _run,
          style: TextStyle(fontSize: 16, color: palette.text),
          decoration: InputDecoration(
            hintText: '名称 / MPN / C编号 / 封装 / 备注',
            border: InputBorder.none,
            filled: false,
            isDense: true,
            hintStyle: TextStyle(fontSize: 14, color: palette.textSub),
          ),
        ),
        actions: [
          if (_keyword.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '清空',
              onPressed: () {
                _controller.clear();
                _run('');
              },
            ),
        ],
      ),
      body: _keyword.isEmpty
          ? const EmptyState(
              icon: Icons.search,
              message: '输入关键词搜索库内物料',
            )
          : FutureBuilder<List<MaterialItem>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snapshot.data ?? const <MaterialItem>[];
                if (items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.search_off,
                    message: '没有匹配的物料',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return MaterialCard(
                      item: item,
                      lowStock: appState.isLowStock(item),
                      iconKey: item.categoryIcon,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MaterialDetailPage(
                            materialId: item.id!,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
