import 'package:flutter/material.dart';

const _serif = 'SafarSerif';

@immutable
class SafarPalette extends ThemeExtension<SafarPalette> {
  const SafarPalette({
    required this.paper,
    required this.surface,
    required this.raised,
    required this.ink,
    required this.muted,
    required this.faint,
    required this.line,
    required this.ember,
    required this.emberSoft,
    required this.jade,
    required this.jadeSoft,
    required this.rose,
    required this.shadow,
  });

  final Color paper;
  final Color surface;
  final Color raised;
  final Color ink;
  final Color muted;
  final Color faint;
  final Color line;
  final Color ember;
  final Color emberSoft;
  final Color jade;
  final Color jadeSoft;
  final Color rose;
  final Color shadow;

  static const light = SafarPalette(
    paper: Color(0xFFF6F1E7),
    surface: Color(0xFFFFFDF8),
    raised: Color(0xFFFAF6EE),
    ink: Color(0xFF1A1812),
    muted: Color(0xFF5C564A),
    faint: Color(0xFF736B5C),
    line: Color(0xFFE3DAC9),
    ember: Color(0xFFB04A08),
    emberSoft: Color(0xFFF7E8D0),
    jade: Color(0xFF0A6E66),
    jadeSoft: Color(0xFFD4EDE7),
    rose: Color(0xFFB01A1A),
    shadow: Color(0xFF483A22),
  );

  static const dark = SafarPalette(
    paper: Color(0xFF12110E),
    surface: Color(0xFF1B1915),
    raised: Color(0xFF24211B),
    ink: Color(0xFFF5EFE3),
    muted: Color(0xFFB0A89A),
    faint: Color(0xFF948C7E),
    line: Color(0xFF3A352C),
    ember: Color(0xFFF0A34A),
    emberSoft: Color(0xFF402D18),
    jade: Color(0xFF5EEAD4),
    jadeSoft: Color(0xFF12342F),
    rose: Color(0xFFF87171),
    shadow: Color(0xFF000000),
  );

  @override
  SafarPalette copyWith({
    Color? paper,
    Color? surface,
    Color? raised,
    Color? ink,
    Color? muted,
    Color? faint,
    Color? line,
    Color? ember,
    Color? emberSoft,
    Color? jade,
    Color? jadeSoft,
    Color? rose,
    Color? shadow,
  }) => SafarPalette(
    paper: paper ?? this.paper,
    surface: surface ?? this.surface,
    raised: raised ?? this.raised,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    faint: faint ?? this.faint,
    line: line ?? this.line,
    ember: ember ?? this.ember,
    emberSoft: emberSoft ?? this.emberSoft,
    jade: jade ?? this.jade,
    jadeSoft: jadeSoft ?? this.jadeSoft,
    rose: rose ?? this.rose,
    shadow: shadow ?? this.shadow,
  );

  @override
  SafarPalette lerp(covariant SafarPalette? other, double t) {
    if (other == null) return this;
    return SafarPalette(
      paper: Color.lerp(paper, other.paper, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      raised: Color.lerp(raised, other.raised, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      faint: Color.lerp(faint, other.faint, t)!,
      line: Color.lerp(line, other.line, t)!,
      ember: Color.lerp(ember, other.ember, t)!,
      emberSoft: Color.lerp(emberSoft, other.emberSoft, t)!,
      jade: Color.lerp(jade, other.jade, t)!,
      jadeSoft: Color.lerp(jadeSoft, other.jadeSoft, t)!,
      rose: Color.lerp(rose, other.rose, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

extension SafarThemeContext on BuildContext {
  SafarPalette get safar =>
      Theme.of(this).extension<SafarPalette>() ?? SafarPalette.light;
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get texts => Theme.of(this).textTheme;
}

class SafarTheme {
  static ThemeData light() => _build(
    brightness: Brightness.light,
    palette: SafarPalette.light,
  );

  static ThemeData dark() => _build(
    brightness: Brightness.dark,
    palette: SafarPalette.dark,
  );

  static ThemeData _build({
    required Brightness brightness,
    required SafarPalette palette,
  }) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: palette.ink,
      onPrimary: palette.surface,
      primaryContainer: palette.emberSoft,
      onPrimaryContainer: palette.ink,
      secondary: palette.ember,
      onSecondary: palette.surface,
      secondaryContainer: palette.emberSoft,
      onSecondaryContainer: palette.ink,
      tertiary: palette.jade,
      onTertiary: palette.surface,
      tertiaryContainer: palette.jadeSoft,
      onTertiaryContainer: palette.ink,
      error: palette.rose,
      onError: palette.surface,
      surface: palette.paper,
      onSurface: palette.ink,
      surfaceContainerHighest: palette.raised,
      surfaceContainerHigh: palette.raised,
      surfaceContainer: palette.surface,
      outline: palette.line,
      outlineVariant: palette.line,
      shadow: palette.shadow,
      scrim: palette.ink,
      inverseSurface: palette.ink,
      onInverseSurface: palette.surface,
      inversePrimary: palette.surface,
    );

    final text = _textTheme(palette);
    final stadium = const StadiumBorder();

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.paper,
      canvasColor: palette.paper,
      textTheme: text,
      extensions: [palette],
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: palette.paper,
        foregroundColor: palette.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: _serif,
          fontSize: 21,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.4,
          color: palette.ink,
        ),
        iconTheme: IconThemeData(color: palette.ink, size: 22),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.ink,
          foregroundColor: palette.surface,
          disabledBackgroundColor: palette.line,
          disabledForegroundColor: palette.faint,
          minimumSize: const Size(44, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          shape: stadium,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.ink,
          side: BorderSide(color: palette.line),
          minimumSize: const Size(44, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          shape: stadium,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.ink,
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: palette.ink,
          minimumSize: const Size(44, 44),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.raised,
        hintStyle: TextStyle(color: palette.faint, fontSize: 14),
        labelStyle: TextStyle(color: palette.muted, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.ember, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.rose),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.rose, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.surface,
        selectedColor: palette.emberSoft,
        disabledColor: palette.raised,
        side: BorderSide(color: palette.line),
        shape: stadium,
        labelStyle: TextStyle(
          color: palette.muted,
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
        ),
        secondaryLabelStyle: TextStyle(
          color: palette.ink,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      dividerTheme: DividerThemeData(
        color: palette.line,
        thickness: 1,
        space: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: palette.emberSoft,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? palette.ink
                : palette.muted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? palette.ink
                : palette.muted,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: palette.line,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.ink,
        contentTextStyle: TextStyle(color: palette.surface, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.ember,
        linearTrackColor: palette.line,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: palette.ink,
        inactiveTrackColor: palette.line,
        thumbColor: palette.ink,
        overlayColor: palette.ember.withValues(alpha: 0.12),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.surface
              : palette.faint,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? palette.ink
              : palette.line,
        ),
      ),
    );
  }

  static TextTheme _textTheme(SafarPalette palette) {
    TextStyle serif(double size, double height, FontWeight weight) =>
        TextStyle(
          fontFamily: _serif,
          fontSize: size,
          height: height / size,
          fontWeight: weight,
          letterSpacing: -0.3,
          color: palette.ink,
        );

    return TextTheme(
      displayLarge: serif(44, 50, FontWeight.w500),
      displayMedium: serif(36, 42, FontWeight.w500),
      displaySmall: serif(30, 36, FontWeight.w500),
      headlineLarge: serif(27, 33, FontWeight.w500),
      headlineMedium: serif(23, 29, FontWeight.w500),
      headlineSmall: serif(20, 26, FontWeight.w500),
      titleLarge: serif(18, 24, FontWeight.w600),
      titleMedium: TextStyle(
        fontSize: 15.5,
        height: 22 / 15.5,
        fontWeight: FontWeight.w600,
        color: palette.ink,
        letterSpacing: -0.1,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        height: 20 / 14,
        fontWeight: FontWeight.w600,
        color: palette.ink,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        height: 1.5,
        color: palette.ink,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 21 / 14,
        color: palette.ink,
      ),
      bodySmall: TextStyle(
        fontSize: 12.5,
        height: 19 / 12.5,
        color: palette.muted,
      ),
      labelLarge: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.02,
        color: palette.muted,
      ),
      labelSmall: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.04,
        color: palette.faint,
      ),
    );
  }
}
