import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../data/repositories/location_repository.dart';
import '../data/repositories/material_repository.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/dialogs.dart';
import '../widgets/material_card.dart';
import '../widgets/stat_card.dart';
import 'inbound_page.dart';
import 'material_detail_page.dart';

/// P6 仓库详情页（线框 07）。
class LocationDetailPage extends StatefulWidget {
  const LocationDetailPage({super.key, required this.locationId});

  final int locationId;

  @override
  State<LocationDetailPage> createState() => _LocationDetailPageState();
}

class _LocationDetailData {
  const _LocationDetailData(this.location, this.materials);

  final Location? location;
  final List<MaterialItem> materials;
}

class _LocationDetailPageState extends State<LocationDetailPage> {
  late Future<_LocationDetailData> _future = _load();
  int _revision = -1;

  Future<_LocationDetailData> _load() async {
    final location = await LocationRepository.stats(widget.locationId);
    final materials = await MaterialRepository.byLocation(widget.locationId);
    return _LocationDetailData(location, materials);
  }

  Future<void> _editNote(Location location) async {
    final note = await showTextDialog(
      context,
      title: '仓库备注',
      initial: location.note,
      hint: '如：靠窗第二层',
      maxLines: 3,
    );
    if (note == null) return;
    await LocationRepository.updateNote(location.id!, note);
    if (!mounted) return;
    context.read<AppState>().notifyDataChanged();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final appState = context.watch<AppState>();
    if (appState.revision != _revision) {
      _revision = appState.revision;
      _future = _load();
    }

    return Scaffold(
      appBar: AppBar(title: Text('仓库详情')),
      body: FutureBuilder<_LocationDetailData>(
        future: _future,
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final location = data.location;
          final materials = data.materials;
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    StatCard(
                      rows: [
                        StatRow(
                          label: '仓库名称',
                          value: location?.name ?? '—',
                        ),
                        StatRow(
                          label: '物料总数',
                          value: formatQty(
                            location?.totalRemaining ?? 0,
                          ),
                        ),
                        StatRow(
                          label: '物料类别',
                          value: '${location?.materialKinds ?? 0} 种',
                        ),
                        StatRow(
                          label: '备注',
                          value: location?.note ?? '',
                          secondary: true,
                          onTap: location == null
                              ? null
                              : () => _editNote(location),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Text(
                          '物料',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: palette.text,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '共 ${materials.length} 种',
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.textSub,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (materials.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          '该仓库还没有物料',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: palette.textSub,
                          ),
                        ),
                      )
                    else
                      for (final item in materials) ...[
                        MaterialCard(
                          item: item,
                          lowStock: appState.isLowStock(item),
                          iconKey: item.categoryIcon,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  MaterialDetailPage(materialId: item.id!),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          InboundPage(presetLocationId: widget.locationId),
                    ),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('添加物料'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
