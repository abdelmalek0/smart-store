import 'package:flutter/material.dart';
import 'package:smart_store_linux/ui/utils/theme/app_theme.dart';

class ModernSidebarBtn extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isExpanded;

  const ModernSidebarBtn({
    super.key,
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.isExpanded = true,
  });

  @override
  State<ModernSidebarBtn> createState() => _ModernSidebarBtnState();
}

class _ModernSidebarBtnState extends State<ModernSidebarBtn> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.isSelected
        ? AppTheme.accent
        : AppTheme.text.withValues(alpha: 0.7);
    final bgColor = widget.isSelected
        ? AppTheme.accent.withValues(alpha: 0.1)
        : _isHovered
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            border: widget.isSelected
                ? Border.all(color: AppTheme.accent.withValues(alpha: 0.3))
                : Border.all(color: Colors.transparent),
          ),
          child: Row(
            mainAxisAlignment: widget.isExpanded
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: [
              Icon(widget.icon, color: color, size: 20),
              if (widget.isExpanded) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      color: color,
                      fontWeight: widget.isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
