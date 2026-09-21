import 'package:flutter/material.dart';

import '../pages/category_page.dart';
import '../pages/home_page.dart';
import '../pages/location_page.dart';
import '../pages/profile_page.dart';
import '../theme/app_theme.dart';

/// 一级页面索引。
class RootPage {
  static const int home = 0;
  static const int category = 1;
  static const int location = 2;
  static const int profile = 3;
}

/// 切到某个一级页面（替换整个栈，避免层级堆叠）。
void openRootPage(BuildContext context, int index, {int? currentIndex}) {
  final navigator = Navigator.of(context);
  if (currentIndex != null) {
    Navigator.of(context).pop();
    if (index == currentIndex) return;
  }
  final page = switch (index) {
    RootPage.category => const CategoryPage(),
    RootPage.location => const LocationPage(),
    RootPage.profile => const ProfilePage(),
    _ => const HomePage(),
  };
  navigator.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => page),
    (route) => false,
  );
}

/// 抽屉开关按钮（☰），放在各一级页面 AppBar 左侧。
class DrawerMenuButton extends StatelessWidget {
  const DrawerMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) => IconButton(
        icon: const Icon(Icons.menu),
        tooltip: '菜单',
        onPressed: () => Scaffold.of(context).openDrawer(),
      ),
    );
  }
}

/// 抽屉导航（首页 / 分类 / 仓库 / 我的），对应线框 02。
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final width = MediaQuery.sizeOf(context).width * 0.78;

    return Drawer(
      width: width,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: palette.primary.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.inventory_2, color: palette.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PartBox',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: palette.text,
                          ),
                        ),
                        Text(
                          '元件盒',
                          style: TextStyle(fontSize: 12, color: palette.textSub),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: palette.border, height: 1),
            const SizedBox(height: 8),
            _Item(
              icon: Icons.home_outlined,
              label: '首页',
              selected: current == RootPage.home,
              onTap: () => openRootPage(
                context,
                RootPage.home,
                currentIndex: current,
              ),
            ),
            _Item(
              icon: Icons.grid_view_outlined,
              label: '分类',
              selected: current == RootPage.category,
              onTap: () => openRootPage(
                context,
                RootPage.category,
                currentIndex: current,
              ),
            ),
            _Item(
              icon: Icons.warehouse_outlined,
              label: '仓库',
              selected: current == RootPage.location,
              onTap: () => openRootPage(
                context,
                RootPage.location,
                currentIndex: current,
              ),
            ),
            const Spacer(),
            Divider(color: palette.border, height: 1),
            _Item(
              icon: Icons.person_outline,
              label: '我的',
              selected: current == RootPage.profile,
              onTap: () => openRootPage(
                context,
                RootPage.profile,
                currentIndex: current,
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected
            ? palette.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(
                  icon,
                  size: 24,
                  color: selected ? palette.primary : palette.textSub,
                ),
                const SizedBox(width: 16),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? palette.primary : palette.text,
                  ),
                ),
                const Spacer(),
                if (selected)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: palette.primary,
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
