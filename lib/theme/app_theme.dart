import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 桌面端（Windows/macOS/Linux）显式指定字体族。
///
/// 不指定时 Flutter 完全交给引擎自动回退：Windows 上中文会落到**宋体**（衬线），
/// 和 UI 规范第 3 节要求的「Windows Segoe UI 系」不符。这里写明
/// 西文 Segoe UI + 中文微软雅黑，两端表现才一致、也不会随系统/引擎变化而漂。
/// Android / iOS 保持系统默认字体，不加干预。
final bool _isDesktop = !Platform.isAndroid && !Platform.isIOS;

final String? _desktopFontFamily = _isDesktop ? 'Segoe UI' : null;

final List<String>? _desktopFontFallback = _isDesktop
    ? const ['Microsoft YaHei UI', 'Microsoft YaHei']
    : null;

/// 组件主题里手写的 TextStyle **不会**继承 `ThemeData.fontFamilyFallback`
/// （只有默认 textTheme 会被打上），所以统一用这个工厂包一层。
TextStyle _style({double? fontSize, FontWeight? fontWeight, Color? color}) =>
    TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      fontFamily: _desktopFontFamily,
      fontFamilyFallback: _desktopFontFallback,
    );

/// 工程风色板（对应《UI 设计规范 v2.0》第 2 节）。
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.primary,
    required this.success,
    required this.warning,
    required this.danger,
    required this.bg,
    required this.card,
    required this.border,
    required this.text,
    required this.textSub,
  });

  final Brightness brightness;
  final Color primary;
  final Color success;
  final Color warning;
  final Color danger;
  final Color bg;
  final Color card;
  final Color border;
  final Color text;
  final Color textSub;

  bool get isDark => brightness == Brightness.dark;

  static const AppPalette light = AppPalette(
    brightness: Brightness.light,
    primary: Color(0xFF2563EB),
    success: Color(0xFF16A34A),
    warning: Color(0xFFEA580C),
    danger: Color(0xFFDC2626),
    bg: Color(0xFFF6F7F9),
    card: Color(0xFFFFFFFF),
    border: Color(0xFFE2E8F0),
    text: Color(0xFF1E293B),
    textSub: Color(0xFF64748B),
  );

  static const AppPalette dark = AppPalette(
    brightness: Brightness.dark,
    primary: Color(0xFF3B82F6),
    success: Color(0xFF22C55E),
    warning: Color(0xFFFB923C),
    danger: Color(0xFFF87171),
    bg: Color(0xFF0F172A),
    card: Color(0xFF1E293B),
    border: Color(0xFF334155),
    text: Color(0xFFE2E8F0),
    textSub: Color(0xFF94A3B8),
  );

  static AppPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  /// 分类图标底色（按名称散列取色）。
  Color tintFor(String? key) {
    const colors = [
      Color(0xFF2563EB),
      Color(0xFF7C3AED),
      Color(0xFF0891B2),
      Color(0xFF16A34A),
      Color(0xFFCA8A04),
      Color(0xFFEA580C),
      Color(0xFFDC2626),
      Color(0xFFDB2777),
      Color(0xFF0D9488),
      Color(0xFF4F46E5),
    ];
    if (key == null || key.isEmpty) return colors.first;
    var hash = 0;
    for (final code in key.codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return colors[hash % colors.length];
  }
}

extension PaletteX on BuildContext {
  AppPalette get palette => AppPalette.of(this);
}

/// 桌面端（Windows）允许用鼠标直接拖动滚动，横向筛选区也能按住拖动。
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad,
  };
}

/// Material 3 主题（深色工程风为默认）。
class AppTheme {
  static ThemeData light() => _build(AppPalette.light);

  static ThemeData dark() => _build(AppPalette.dark);

  static ThemeData _build(AppPalette p) {
    final scheme = ColorScheme(
      brightness: p.brightness,
      primary: p.primary,
      onPrimary: Colors.white,
      secondary: p.primary,
      onSecondary: Colors.white,
      error: p.danger,
      onError: Colors.white,
      surface: p.card,
      onSurface: p.text,
    );

    final radiusCard = BorderRadius.circular(12);
    final radiusField = BorderRadius.circular(8);

    return ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.bg,
      canvasColor: p.bg,
      fontFamily: _desktopFontFamily,
      fontFamilyFallback: _desktopFontFallback,
      splashFactory: InkRipple.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: p.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: p.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: p.text, size: 24),
        titleTextStyle: _style(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: p.text,
        ),
      ),
      cardTheme: CardThemeData(
        color: p.card,
        elevation: p.isDark ? 0 : 1,
        shadowColor: Colors.black12,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: radiusCard,
          side: BorderSide(color: p.isDark ? p.border : const Color(0xFFEDF0F4)),
        ),
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      drawerTheme: DrawerThemeData(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(12),
            bottomRight: Radius.circular(12),
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.textSub,
        textColor: p.text,
        titleTextStyle: _style(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: p.text,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.isDark ? const Color(0xFF16213A) : Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        hintStyle: _style(color: p.textSub, fontSize: 14),
        labelStyle: _style(color: p.textSub, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: radiusField,
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radiusField,
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radiusField,
          borderSide: BorderSide(color: p.primary, width: 1.4),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.isDark ? p.bg : const Color(0xFFF1F5F9),
        selectedColor: p.primary.withValues(alpha: 0.16),
        side: BorderSide(color: p.border),
        labelStyle: _style(fontSize: 13, color: p.text),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          textStyle: _style(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: radiusField),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.text,
          minimumSize: const Size.fromHeight(48),
          side: BorderSide(color: p.border),
          textStyle: _style(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: radiusField),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: p.primary),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.isDark ? const Color(0xFF263449) : const Color(0xFF1E293B),
        contentTextStyle: _style(color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: radiusField),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: radiusCard),
        titleTextStyle: _style(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: p.text,
        ),
        contentTextStyle: _style(fontSize: 14, color: p.text),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.card,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: radiusField),
      ),
      sliderTheme: SliderThemeData(activeTrackColor: p.primary),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll<Color?>(
          p.textSub.withValues(alpha: 0.55),
        ),
        thickness: const WidgetStatePropertyAll<double>(6),
        radius: const Radius.circular(3),
      ),
      extensions: <ThemeExtension<dynamic>>[],
    );
  }
}
