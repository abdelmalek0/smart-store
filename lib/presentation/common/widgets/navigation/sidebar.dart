import 'package:flutter/material.dart';
import 'package:smart_store_linux/presentation/common/utils/theme/app_theme.dart';
import 'package:smart_store_linux/presentation/common/widgets/modern/modern_widgets.dart';

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
          ModernSidebarBtn(
            icon: Icons.dashboard_rounded,
            label: 'Dashboard',
            isSelected: widget.selectedIndex == 0,
            onTap: () => widget.onItemSelected(0),
            isExpanded: widget.isExpanded,
          ),
          ModernSidebarBtn(
            icon: Icons.model_training_rounded,
            label: 'Models',
            isSelected: widget.selectedIndex == 1,
            onTap: () => widget.onItemSelected(1),
            isExpanded: widget.isExpanded,
          ),
          ModernSidebarBtn(
            icon: Icons.video_call_rounded,
            label: 'Streams',
            isSelected: widget.selectedIndex == 2,
            onTap: () => widget.onItemSelected(2),
            isExpanded: widget.isExpanded,
          ),
          ModernSidebarBtn(
            icon: Icons.extension_rounded,
            label: 'Plugins',
            isSelected: widget.selectedIndex == 3,
            onTap: () => widget.onItemSelected(3),
            isExpanded: widget.isExpanded,
          ),
          ModernSidebarBtn(
            icon: Icons.settings_rounded,
            label: 'Configuration',
            isSelected: widget.selectedIndex == 4,
            onTap: () => widget.onItemSelected(4),
            isExpanded: widget.isExpanded,
          ),
          ModernSidebarBtn(
            icon: Icons.live_tv_rounded,
            label: 'Live Monitoring',
            isSelected: widget.selectedIndex == 5,
            onTap: () => widget.onItemSelected(5),
            isExpanded: widget.isExpanded,
          ),
          ModernSidebarBtn(
            icon: Icons.notifications_active_rounded,
            label: 'Events',
            isSelected: widget.selectedIndex == 6,
            onTap: () => widget.onItemSelected(6),
            isExpanded: widget.isExpanded,
          ),
        ],
      ),
    );
  }
}
