/// The security-envelope look: paper ground, ink, and a fine printed tint
/// over anything concealed. Tokens match myvault/ui/app.css.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

class Envelope extends ThemeExtension<Envelope> {
  final Color paper,
      panel,
      sheet,
      ink,
      ink2,
      ink3,
      rule,
      rule2,
      tint,
      tintWash,
      red,
      ok;
  const Envelope({
    required this.paper,
    required this.panel,
    required this.sheet,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.rule,
    required this.rule2,
    required this.tint,
    required this.tintWash,
    required this.red,
    required this.ok,
  });

  static const light = Envelope(
    paper: Color(0xFFF4F5F7),
    panel: Color(0xFFECEEF2),
    sheet: Color(0xFFFBFBFC),
    ink: Color(0xFF1B2433),
    ink2: Color(0xFF47526A),
    ink3: Color(0xFF5F687A),
    rule: Color(0xFFD5DAE3),
    rule2: Color(0xFFC2C9D6),
    tint: Color(0xFF2F4A7A),
    tintWash: Color(0xFFE4E9F2),
    red: Color(0xFFB4432E),
    ok: Color(0xFF2D6A4A),
  );
  static const dark = Envelope(
    paper: Color(0xFF12161E),
    panel: Color(0xFF161B24),
    sheet: Color(0xFF1A202A),
    ink: Color(0xFFE6EAF2),
    ink2: Color(0xFFB3BBC9),
    ink3: Color(0xFF959EAF),
    rule: Color(0xFF2A3242),
    rule2: Color(0xFF384256),
    tint: Color(0xFF7E98CC),
    tintWash: Color(0xFF222B3B),
    red: Color(0xFFE5866F),
    ok: Color(0xFF7CC29B),
  );

  static Envelope of(BuildContext c) => Theme.of(c).extension<Envelope>()!;

  @override
  Envelope copyWith() => this;
  @override
  Envelope lerp(ThemeExtension<Envelope>? other, double t) =>
      t < .5 ? this : (other as Envelope? ?? this);
}

ThemeData buildTheme(Envelope e, Brightness b) {
  final scheme = ColorScheme(
    brightness: b,
    primary: e.ink,
    onPrimary: e.paper,
    secondary: e.tint,
    onSecondary: e.paper,
    error: e.red,
    onError: Colors.white,
    surface: e.sheet,
    onSurface: e.ink,
    surfaceContainerHighest: e.panel,
    outline: e.rule2,
    outlineVariant: e.rule,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(6));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: e.sheet,
    extensions: [e],
    dividerTheme: DividerThemeData(color: e.rule, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: e.panel,
      foregroundColor: e.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: Border(bottom: BorderSide(color: e.rule)),
      titleTextStyle: TextStyle(
        color: e.ink,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: e.sheet,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      labelStyle: TextStyle(color: e.ink2),
      hintStyle: TextStyle(color: e.ink3),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: e.rule2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: e.rule2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: e.tint, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: e.ink,
        foregroundColor: e.paper,
        shape: shape,
        minimumSize: const Size(64, 46),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: e.ink,
        side: BorderSide(color: e.rule2),
        shape: shape,
        minimumSize: const Size(64, 46),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: e.ink, shape: shape),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.transparent,
      selectedColor: e.ink,
      side: BorderSide(color: e.rule2),
      labelStyle: TextStyle(color: e.ink2, fontSize: 13),
      secondaryLabelStyle: TextStyle(color: e.paper, fontSize: 13),
      shape: const StadiumBorder(),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? e.paper : e.ink3,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? e.ink : Colors.transparent,
      ),
      trackOutlineColor: WidgetStatePropertyAll(e.ink3),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: e.ink,
      inactiveTrackColor: e.rule2,
      thumbColor: e.ink,
      overlayColor: e.tint.withAlpha(30),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: e.ink,
      contentTextStyle: TextStyle(color: e.paper),
      behavior: SnackBarBehavior.floating,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: e.sheet,
      showDragHandle: true,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: e.ink,
      foregroundColor: e.paper,
      elevation: 2,
      highlightElevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: e.tint,
      selectionColor: e.tint.withAlpha(70),
      selectionHandleColor: e.tint,
    ),
  );
}

/// The printed security tint: fine sine-wave linework, optionally crossed by a
/// second, slower vertical wave (that crossing is what makes it read as a tint).
class TintPainter extends CustomPainter {
  final Color color;
  final double opacity;
  final bool crossed;
  const TintPainter(this.color, {this.opacity = .4, this.crossed = false});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8;
    const wl = 14.0, amp = 1.4, gap = 3.5;
    for (var y = 0.0; y < size.height + gap; y += gap) {
      final path = Path()..moveTo(0, y);
      for (var x = 0.0; x <= size.width; x += 2) {
        path.lineTo(x, y + amp * math.sin(x / wl * 2 * math.pi));
      }
      canvas.drawPath(path, p);
    }
    if (!crossed) return;
    p.color = color.withValues(alpha: opacity * .6);
    p.strokeWidth = .7;
    for (var x = 0.0; x < size.width + 11; x += 11) {
      final path = Path()..moveTo(x, 0);
      for (var y = 0.0; y <= size.height; y += 3) {
        path.lineTo(x + 4 * math.sin(y / 44 * 2 * math.pi), y);
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(TintPainter old) =>
      old.color != color || old.opacity != opacity;
}

/// The little envelope mark used as the wordmark glyph.
class EnvelopeMark extends StatelessWidget {
  final double width;
  const EnvelopeMark({super.key, this.width = 28});
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(width, width * 22 / 30),
    painter: _MarkPainter(Envelope.of(context).ink),
  );
}

class _MarkPainter extends CustomPainter {
  final Color c;
  _MarkPainter(this.c);
  @override
  void paint(Canvas canvas, Size s) {
    final k = s.width / 30;
    final p = Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * k
      ..strokeJoin = StrokeJoin.round;
    canvas.drawRRect(
      RRect.fromLTRBR(1 * k, 1 * k, 29 * k, 21 * k, Radius.circular(2.5 * k)),
      p,
    );
    canvas.drawPath(
      Path()
        ..moveTo(1.5 * k, 2 * k)
        ..lineTo(15 * k, 12 * k)
        ..lineTo(28.5 * k, 2 * k),
      p,
    );
  }

  @override
  bool shouldRepaint(_MarkPainter o) => o.c != c;
}
