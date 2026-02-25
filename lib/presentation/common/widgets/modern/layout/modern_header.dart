import 'package:flutter/material.dart';
import 'package:smart_store_linux/presentation/common/utils/theme/app_theme.dart';

class ModernHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget>? actions;

  const ModernHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.background,
        border: Border(bottom: BorderSide(color: AppTheme.surface, width: 1)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.text,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.text.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ],
          ),
          const Spacer(),
          if (actions != null) ...actions!,
        ],
      ),
    );
  }
}
