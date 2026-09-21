import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../data/lcsc/lcsc_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';

/// P8 扫码页（仅 Android，支持连续扫描）。
///
/// 返回值为扫描到的 C 编号列表。
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

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

  final List<String> _codes = [];
  bool _continuous = true;
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
      var code = LcscService.normalizeCode(raw);
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
      final resolved = code;

      if (!_continuous) {
        if (!mounted) return;
        Navigator.of(context).pop([resolved]);
        return;
      }
      if (_codes.contains(resolved)) return;
      setState(() => _codes.insert(0, resolved));
      if (mounted) showToast(context, '已记录 $resolved');
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
                            '本次扫描 ${_codes.length} 个',
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
                        child: _codes.isEmpty
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
                                itemCount: _codes.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (context, index) => Center(
                                  child: Chip(
                                    label: Text(_codes[index]),
                                    onDeleted: () => setState(
                                      () => _codes.removeAt(index),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: () =>
                            Navigator.of(context).pop(List<String>.from(_codes)),
                        child: Text(
                          _codes.isEmpty ? '返回' : '完成（${_codes.length}）',
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
