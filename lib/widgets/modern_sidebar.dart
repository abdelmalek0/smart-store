import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:smart_store_linux/theme/app_theme.dart';
import 'package:smart_store_linux/widgets/modern_widgets.dart';

class ModernSidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final bool isExpanded;
  final VoidCallback onToggle;

  const ModernSidebar({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: isExpanded ? 240 : 70,
      color: AppTheme.sidebar,
      child: Column(
        children: [
          const SizedBox(height: 20),
          // Logo / Toggle
          Row(
            mainAxisAlignment: isExpanded
                ? MainAxisAlignment.spaceBetween
                : MainAxisAlignment.center,
            children: [
              if (isExpanded)
                const Padding(
                  padding: EdgeInsets.only(left: 20),
                  child: Text(
                    "Smart Store",
                    style: TextStyle(
                      color: AppTheme.primary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              IconButton(
                icon: Icon(
                  isExpanded
                      ? CupertinoIcons.sidebar_left
                      : CupertinoIcons.sidebar_right,
                  color: AppTheme.text,
                ),
                onPressed: onToggle,
              ),
            ],
          ),
          const SizedBox(height: 30),
          Expanded(
            child: ListView(
              children: [
                _buildNavItem(0, CupertinoIcons.speedometer, "Dashboard"),
                _buildNavItem(1, CupertinoIcons.layers_alt, "Models"),
                _buildNavItem(2, CupertinoIcons.video_camera, "Streams"),
                _buildNavItem(3, CupertinoIcons.settings, "Configuration"),
                _buildNavItem(4, CupertinoIcons.play_circle, "Playback"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    return ModernSidebarBtn(
      icon: icon,
      label: label,
      isSelected: selectedIndex == index,
      isExpanded: isExpanded,
      onTap: () => onItemSelected(index),
    );
  }
}
