import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
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
          _buildNavItem(0, 'Dashboard', CupertinoIcons.chart_bar_alt_fill),
          _buildNavItem(1, 'Models', CupertinoIcons.cube_box),
          _buildNavItem(2, 'Streams', CupertinoIcons.videocam_fill),
          _buildNavItem(3, 'Configuration', CupertinoIcons.settings),
          _buildNavItem(4, 'Playback', CupertinoIcons.play_circle_fill),
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
              ? AppTheme.primary.withOpacity(0.2)
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
                  : AppTheme.text.withOpacity(0.7),
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
                        : AppTheme.text.withOpacity(0.9),
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
