import 'package:flutter/material.dart';
import 'package:smart_store_linux/ui/theme/app_theme.dart';

class Sidebar extends StatefulWidget {
  final int selectedIndex;
  final Function(int) onItemSelected;
  final bool isExpanded;
  final VoidCallback onToggle;

  const Sidebar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: widget.isExpanded ? 250 : 70,
      color: AppTheme.sidebar,
      child: Column(
        children: [
          // Header
          SizedBox(
            height: 60,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.menu, color: AppTheme.text),
                  onPressed: widget.onToggle,
                ),
                if (widget.isExpanded)
                  Expanded(
                    child: Text(
                      'Smart Store',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.fade,
                      softWrap: false,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(color: AppTheme.surface, height: 1),
          const SizedBox(height: 10),
          // Navigation Items
          _buildNavItem(0, 'Dashboard', Icons.dashboard_rounded),
          _buildNavItem(1, 'Models', Icons.model_training_rounded),
          _buildNavItem(2, 'Streams', Icons.video_call_rounded),
          _buildNavItem(3, 'Plugins', Icons.extension_rounded),
          _buildNavItem(4, 'Configuration', Icons.settings_rounded),
          _buildNavItem(5, 'Live Monitoring', Icons.live_tv_rounded),
          _buildNavItem(6, 'Events', Icons.notifications_active_rounded),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, String title, IconData icon) {
    final isSelected = widget.selectedIndex == index;
    return InkWell(
      onTap: () => widget.onItemSelected(index),
      child: Container(
        height: 50,
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const SizedBox(width: 10),
            Icon(
              icon,
              color: isSelected
                  ? AppTheme.primary
                  : AppTheme.text.withValues(alpha: 0.7),
              size: 24,
            ),
            if (widget.isExpanded) ...[
              const SizedBox(width: 15),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: isSelected
                        ? AppTheme.primary
                        : AppTheme.text.withValues(alpha: 0.9),
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
