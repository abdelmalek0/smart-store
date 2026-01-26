import 'package:flutter/material.dart';
import 'package:smart_store_linux/ui/theme/app_theme.dart';
import 'package:smart_store_linux/ui/widgets/modern_widgets.dart';

// Helper for consistent Empty States
Widget buildEmptyState(
  BuildContext context,
  String message, {
  String? buttonLabel,
  VoidCallback? onAction,
  IconData? icon,
}) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          icon ?? Icons.inbox_outlined,
          size: 64,
          color: AppTheme.text.withValues(alpha: 0.2),
        ),
        const SizedBox(height: 16),
        ModernLabel(
          message,
          color: AppTheme.text.withValues(alpha: 0.5),
          fontSize: 16,
        ),
        if (buttonLabel != null && onAction != null) ...[
          const SizedBox(height: 24),
          ModernButton(
            label: buttonLabel,
            icon: Icons.add,
            onPressed: onAction,
          ),
        ],
      ],
    ),
  );
}
