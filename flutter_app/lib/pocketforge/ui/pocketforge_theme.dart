import 'package:fa_ui/fa_ui.dart';
import 'package:flutter/material.dart';

/// A quiet editor palette shared by the product shell and Fa's message tiles.
final pocketForgeUiTheme = FaUiTheme(
  indigo: const Color(0xFF8CDAC3),
  teal: const Color(0xFF8CDAC3),
  background: const Color(0xFF111314),
  surface: const Color(0xFF191C1D),
  userBubble: const Color(0xFF24292A),
  userBubbleBorder: const Color(0xFF353D3E),
  cardRadius: 12,
  inputRadius: 12,
  buttonRadius: 10,
  darkPalette: FahColors.dark.override(
    bg: const Color(0xFF111314),
    bgAlt: const Color(0xFF151819),
    panel: const Color(0xFF191C1D),
    panelAlt: const Color(0xFF222728),
    border: const Color(0xFF2C3233),
    borderBright: const Color(0xFF424C4D),
    text: const Color(0xFFE8EDEC),
    dim: const Color(0xFF9AA6A4),
    onAccent: const Color(0xFF10231D),
    error: const Color(0xFFF39D95),
    codeBg: const Color(0xFF151819),
  ),
);

TextStyle forgeMono(BuildContext context, {Color? color, double size = 11}) =>
    Theme.of(context).textTheme.bodySmall!.copyWith(
      fontFamily: 'JetBrainsMono',
      color: color ?? FahColors.of(context).dim,
      fontSize: size,
      height: 1.5,
    );
