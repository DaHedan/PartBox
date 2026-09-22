import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../data/lcsc/lcsc_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/scan_payload.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';

/// P8 扫码页（仅 Android，支持连续扫描）。
///
/// 返回值为扫描结果列表 [ScanPayload]（C 编号 + 标签带出的 MPN / 数量）。
class ScanPage extends StatefulWidget {
  const ScanPage({super.key, this.initialContinuous = true});

  /// 连续扫描开关初始状态。入库流程用单次扫描（扫一包立刻带回数量）。
  final bool initialContinuous;

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.qrCode,
      BarcodeFormat.code128,
      BarcodeFormat.dataMatrix,
      BarcodeFormat.code39,
      BarcodeFormat.ean13,
    ],
  );

  final List<ScanPayload> _hits = [];
  late bool _continuous = widget.initialContinuous;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.trim().isEmpty) continue;
      await _handleRaw(raw.trim());
      return;
    }
  }

  Future<void> _handleRaw(String raw) async {
    _busy = true;
    try {
      // 立创袋标二维码：pc → C 编号，pm → MPN，qty → 数量
      final label = parseLcscLabel(raw);
      var code = label?.code;
      if (code == null) {
        // 批次追溯码（X+数字）：扫错了，提示改扫标签二维码
        if (isBatchTraceCode(raw)) {
          if (mounted) showToast(context, '这是批次追溯码，请扫标签上的二维码');
          return;
        }
        code = LcscService.normalizeCode(raw);
      }
      if (code == null) {
        if (!mounted) return;
        final edited = await showTextDialog(
          context,
          title: '未识别到 C 编号',
          initial: raw,
          hint: '可手动截取，如 C106248',
        );
        if (edited == null) return;
        code = LcscService.normalizeCode(edited) ?? edited.trim();
      }
      if (code.isEmpty) return;
      final hit = ScanPayload(
        code: code,
        mpn: label?.mpn,
        qty: label?.qty,
        raw: raw,
      );

      if (!_continuous) {
        if (!mounted) return;
        Navigator.of(context).pop([hit]);
        return;
      }
      if (_hits.any((e) => e.code == code)) return;
      setState(() => _hits.insert(0, hit));
      if (mounted) {
        showToast(
          context,
          hit.qty == null
              ? '已记录 $code'
              : '已记录 $code（${formatQty(hit.qty!)}）',
        );
      }
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final supported = Platform.isAndroid || Platform.isIOS;

    return Scaffold(
      appBar: AppBar(
        title: const Text('扫码'),
        actions: [
          if (supported)
            Row(
              children: [
                Text(
                  '连续扫描',
                  style: TextStyle(fontSize: 12, color: palette.textSub),
                ),
                Switch(
                  value: _continuous,
                  onChanged: (value) => setState(() => _continuous = value),
                ),
              ],
            ),
        ],
      ),
      body: !supported
          ? const EmptyState(
              icon: Icons.no_photography_outlined,
              message: '当前平台不支持扫码，请使用 C 编号查询或手动录入',
            )
          : Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      MobileScanner(
                        controller: _controller,
                        onDetect: _onDetect,
                        errorBuilder: (context, error) => Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              '相机不可用：${error.errorCode.name}\n请检查相机权限',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: palette.textSub,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              '对准包装标签二维码 / 条形码',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  decoration: BoxDecoration(
                    color: palette.card,
                    border: Border(top: BorderSide(color: palette.border)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text(
                            '本次扫描 ${_hits.length} 个',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: palette.text,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _continuous ? '连续扫描中' : '单次扫描',
                            style: TextStyle(
                              fontSize: 12,
                              color: palette.textSub,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 40,
                        child: _hits.isEmpty
                            ? Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '等待扫描…',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: palette.textSub,
                                  ),
                                ),
                              )
                            : ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: _hits.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (context, index) {
                                  final hit = _hits[index];
                                  return Center(
                                    child: Chip(
                                      label: Text(
                                        hit.qty == null
                                            ? hit.code!
                                            : '${hit.code!} · ${formatQty(hit.qty!)}',
                                      ),
                                      onDeleted: () => setState(
                                        () => _hits.removeAt(index),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: () => Navigator.of(
                          context,
                        ).pop(List<ScanPayload>.from(_hits)),
                        child: Text(
                          _hits.isEmpty ? '返回' : '完成（${_hits.length}）',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
