import 'package:flutter/material.dart';
import 'package:smart_store_linux/ui/utils/theme/app_theme.dart';

class ModernButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool isDestructive;
  final bool isOutline;

  const ModernButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isDestructive = false,
    this.isOutline = false,
  });

  @override
  State<ModernButton> createState() => _ModernButtonState();
}

class _ModernButtonState extends State<ModernButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.isDestructive
        ? AppTheme.destructive
        : AppTheme.primary;
    final bgColor = widget.isOutline
        ? Colors.transparent
        : _isHovered
        ? baseColor.withValues(alpha: 0.8)
        : baseColor;
    final textColor = widget.isOutline ? baseColor : AppTheme.background;
    final borderColor = baseColor;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: textColor, size: 18),
                const SizedBox(width: 8),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
