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

class ModernCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;

  const ModernCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

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
