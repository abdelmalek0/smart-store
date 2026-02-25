import 'package:flutter/material.dart';
import 'package:smart_store_linux/presentation/common/utils/theme/app_theme.dart';

class ModernLabel extends StatelessWidget {
  final String text;
  final Color? color;
  final double fontSize;
  final FontWeight fontWeight;

  const ModernLabel(
    this.text, {
    super.key,
    this.color,
    this.fontSize = 14,
    this.fontWeight = FontWeight.normal,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: color ?? AppTheme.text,
        fontSize: fontSize,
        fontWeight: fontWeight,
      ),
    );
  }
}
