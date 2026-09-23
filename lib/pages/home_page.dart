import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../data/repositories/location_repository.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/app_drawer.dart';
import '../widgets/count_circle.dart';
import 'bom_project_list_page.dart';
import 'inbound_page.dart';
import 'location_detail_page.dart';
import 'search_page.dart';
import 'weld_project_list_page.dart';

/// P1 首页（线框 01）。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<Location>> _future = LocationRepository.all(withStats: true);
  int _revision = -1;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final revision = context.watch<AppState>().revision;
    if (revision != _revision) {
      _revision = revision;
      _future = LocationRepository.all(withStats: true);
    }

    return Scaffold(
      appBar: AppBar(
        leading: const DrawerMenuButton(),
        title: const Text('元件盒'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SearchPage()),
            ),
          ),
        ],
      ),
      drawer: const AppDrawer(current: RootPage.home),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<List<Location>>(
              future: _future,
              builder: (context, snapshot) {
                final locations = snapshot.data ?? const <Location>[];
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  children: [
                    _BigCard(
                      title: 'BOM 对照',
                      subtitle: '导入嘉立创 BOM，四色比对库存后双导出',
                      badge: null,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const BomProjectListPage(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _BigCard(
                      title: '焊接辅助',
                      subtitle: 'iBOM 左清单右板图，边焊边扣',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const WeldProjectListPage(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Text(
                          '仓库速览',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: palette.text,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () =>
                              openRootPage(context, RootPage.location),
                          child: const Text('全部'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Card(
                      child: locations.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: Text('还没有仓库')),
                            )
                          : ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 280),
                              child: ListView.separated(
                                shrinkWrap: true,
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                itemCount: locations.length,
                                separatorBuilder: (_, _) => Divider(
                                  color: palette.border,
                                  height: 1,
                                  indent: 16,
                                  endIndent: 16,
                                ),
                                itemBuilder: (context, index) {
                                  final location = locations[index];
                                  return InkWell(
                                    onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => LocationDetailPage(
                                          locationId: location.id!,
                                        ),
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.inventory_2_outlined,
                                            size: 20,
                                            color: palette.textSub,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              location.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 15,
                                                color: palette.text,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            '${location.materialKinds} 种',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: palette.textSub,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          CountCircle(
                                            count: location.materialKinds,
                                            size: 28,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const InboundPage()),
              ),
              icon: const Icon(Icons.add),
              label: const Text('入库'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 首页大功能卡（UI 规范 6.4）。
class _BigCard extends StatelessWidget {
  const _BigCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge = '预留',
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// 右上角角标；_null_ 表示已正式启用（不显示）。
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          height: 124,
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: palette.text,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: palette.textSub),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 10,
                right: 12,
                child: badge == null
                    ? const SizedBox.shrink()
                    : Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: palette.border.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          badge!,
                          style: TextStyle(fontSize: 11, color: palette.textSub),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
