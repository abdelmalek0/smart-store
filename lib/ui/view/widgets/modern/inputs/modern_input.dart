import 'package:flutter/material.dart';
import 'package:smart_store_linux/ui/utils/theme/app_theme.dart';

class ModernInput extends StatelessWidget {
  final String hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final bool isPassword;

  const ModernInput({
    super.key,
    required this.hint,
    this.controller,
    this.onChanged,
    this.isPassword = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.surface),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        obscureText: isPassword,
        style: const TextStyle(color: AppTheme.text),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hint,
          hintStyle: TextStyle(color: AppTheme.text.withValues(alpha: 0.4)),
        ),
      ),
    );
  }
}
