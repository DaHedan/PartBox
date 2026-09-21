import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/backup_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_drawer.dart';
import '../widgets/dialogs.dart';
import 'category_page.dart';
import 'location_page.dart';

/// P11 我的 / 设置页。
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final appState = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        leading: const DrawerMenuButton(),
        title: const Text('我的'),
      ),
      drawer: const AppDrawer(current: RootPage.profile),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionTitle(title: '外观'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '主题',
                    style: TextStyle(fontSize: 14, color: palette.textSub),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text('跟随系统'),
                      ),
                      ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                      ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
                    ],
                    selected: {appState.themeMode},
                    onSelectionChanged: (selection) =>
                        appState.setThemeMode(selection.first),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _SectionTitle(title: '库存'),
          const SizedBox(height: 8),
          Card(
            child: _SettingRow(
              icon: Icons.warning_amber_outlined,
              title: '全局低库存阈值',
              value: '${appState.lowStockThreshold}',
              onTap: () async {
                final value = await showNumberDialog(
                  context,
                  title: '全局低库存阈值',
                  initial: appState.lowStockThreshold.toDouble(),
                  allowNegative: false,
                );
                if (value == null) return;
                await appState.setLowStockThreshold(value.round());
              },
            ),
          ),
          const SizedBox(height: 20),
          _SectionTitle(title: '立创数据源'),
          const SizedBox(height: 8),
          Card(
            child: _SettingRow(
              icon: Icons.key_outlined,
              title: '开放平台密钥',
              value: appState.lcscApiKey.isEmpty ? '未配置' : '已配置',
              onTap: () async {
                final value = await showTextDialog(
                  context,
                  title: '立创开放平台密钥',
                  initial: appState.lcscApiKey,
                  hint: '留空则使用公开数据源',
                );
                if (value == null) return;
                await appState.setLcscApiKey(value);
              },
            ),
          ),
          const SizedBox(height: 20),
          _SectionTitle(title: '数据管理'),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                _SettingRow(
                  icon: Icons.grid_view_outlined,
                  title: '分类管理',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CategoryPage()),
                  ),
                ),
                Divider(color: palette.border, height: 1, indent: 16),
                _SettingRow(
                  icon: Icons.warehouse_outlined,
                  title: '仓库管理',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LocationPage()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _SectionTitle(title: '备份与恢复'),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                _SettingRow(
                  icon: Icons.upload_file_outlined,
                  title: '导出备份（JSON）',
                  onTap: () => _exportJson(context),
                ),
                Divider(color: palette.border, height: 1, indent: 16),
                _SettingRow(
                  icon: Icons.restore_outlined,
                  title: '导入恢复（JSON）',
                  onTap: () => _importJson(context),
                ),
                Divider(color: palette.border, height: 1, indent: 16),
                _SettingRow(
                  icon: Icons.table_view_outlined,
                  title: '导出物料清单（CSV）',
                  onTap: () => _exportCsv(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _SectionTitle(title: '关于'),
          const SizedBox(height: 8),
          Card(
            child: _SettingRow(
              icon: Icons.info_outline,
              title: 'PartBox 元件盒',
              value: 'v1.0',
              onTap: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('PartBox 元件盒'),
                  content: const Text(
                    '版本 v1.0\n\n电子元器件库存管理工具：立创分类体系、'
                    'C 编号/扫码建档、三量库存与流水、分面筛选、本地备份。\n'
                    '全部数据保存在本机，不联网、不上报。',
                    style: TextStyle(fontSize: 14, height: 1.6),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('知道了'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportJson(BuildContext context) async {
    final content = await BackupService.exportJson();
    final uri = await FilePicker.saveFile(
      dialogTitle: '导出备份',
      fileName: 'partbox_backup_${fileStamp(DateTime.now())}.json',
      bytes: utf8.encode(content),
      mimeType: 'application/json',
    );
    if (uri == null || !context.mounted) return;
    showToast(context, '已导出备份');
  }

  Future<void> _exportCsv(BuildContext context) async {
    final content = await BackupService.exportCsv();
    final uri = await FilePicker.saveFile(
      dialogTitle: '导出物料清单',
      fileName: 'partbox_materials_${fileStamp(DateTime.now())}.csv',
      bytes: utf8.encode(content),
      mimeType: 'text/csv',
    );
    if (uri == null || !context.mounted) return;
    showToast(context, '已导出物料清单');
  }

  Future<void> _importJson(BuildContext context) async {
    final file = await FilePicker.pickFile(
      dialogTitle: '选择备份文件',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (file == null || !context.mounted) return;

    final content = utf8.decode(await file.readAsBytes(), allowMalformed: true);
    if (!context.mounted) return;

    final ok = await showConfirmDialog(
      context,
      title: '导入恢复',
      message: '将覆盖当前全部数据（分类、仓库、物料、流水、设置），确定继续？',
      confirmText: '覆盖导入',
      danger: true,
    );
    if (!ok || !context.mounted) return;

    final appState = context.read<AppState>();
    try {
      final summary = await BackupService.importJson(content);
      await appState.load();
      appState.notifyDataChanged();
      if (!context.mounted) return;
      showToast(
        context,
        '已恢复：物料 ${summary.materialCount} 条、分类 ${summary.categoryCount} 个、仓库 ${summary.locationCount} 个',
      );
    } catch (e) {
      if (!context.mounted) return;
      showToast(context, '恢复失败：$e');
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: palette.text,
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    this.value,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(icon, size: 20, color: palette.textSub),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(fontSize: 15, color: palette.text),
              ),
            ),
            if (value != null)
              Text(
                value!,
                style: TextStyle(fontSize: 13, color: palette.textSub),
              ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, size: 18, color: palette.textSub),
          ],
        ),
      ),
    );
  }
}
