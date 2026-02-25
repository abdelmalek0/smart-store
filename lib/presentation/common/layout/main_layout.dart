import 'package:flutter/material.dart';
import 'package:smart_store_linux/presentation/common/utils/theme/app_theme.dart';
import 'package:smart_store_linux/presentation/common/widgets/navigation/sidebar.dart';
import 'package:smart_store_linux/presentation/features/dashboard/dashboard_screen.dart';
import 'package:smart_store_linux/presentation/features/models/models_screen.dart';
import 'package:smart_store_linux/presentation/features/streams/streams_screen.dart';
import 'package:smart_store_linux/presentation/features/configuration/configuration_screen.dart';

import 'package:smart_store_linux/presentation/features/playback/playback_screen.dart';
import 'package:smart_store_linux/presentation/features/plugins/plugins_screen.dart';
import 'package:smart_store_linux/presentation/features/events_log/events_screen.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const DashboardScreen(),
    const ModelsScreen(),
    const StreamsScreen(),
    const PluginsScreen(),
    const ConfigurationScreen(),
    const PlaybackScreen(),
    const EventsScreen(),
  ];

  bool _isSidebarExpanded = false;

  void _toggleSidebar() {
    setState(() {
      _isSidebarExpanded = !_isSidebarExpanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    // AppProvider still needed for global things if used here, but currently only for sidebar?
    // Actually sidebar logic was the only use.
    // But check if other widgets need AppProvider. Providing it at top level is fine.
    // Provider.of<AppProvider>(context) was only used for sidebar.

    return Scaffold(
      body: Row(
        children: [
          Sidebar(
            selectedIndex: _selectedIndex,
            onItemSelected: (index) => setState(() => _selectedIndex = index),
            isExpanded: _isSidebarExpanded,
            onToggle: _toggleSidebar,
          ),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    color: AppTheme.background,
                    padding: const EdgeInsets.all(20.0),
                    child: IndexedStack(
                      index: _selectedIndex,
                      children: _screens,
                    ),
                  ),
                ),
                // Footer
                Container(
                  height: 30,
                  color: AppTheme.sidebar,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    "Made by Smartprints Team",
                    style: TextStyle(
                      color: AppTheme.text.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
