import 'package:flutter/material.dart';
import 'package:smart_store_linux/ui/utils/theme/app_theme.dart';
import 'package:smart_store_linux/ui/view/widgets/navigation/sidebar.dart';
import 'package:smart_store_linux/ui/view/screens/dashboard_screen.dart';
import 'package:smart_store_linux/ui/view/screens/models_screen.dart';
import 'package:smart_store_linux/ui/view/screens/streams_screen.dart';
import 'package:smart_store_linux/ui/view/screens/configuration_screen.dart';

import 'package:smart_store_linux/ui/view/screens/playback_screen.dart';
import 'package:smart_store_linux/ui/view/screens/plugins_screen.dart';
import 'package:smart_store_linux/ui/view/screens/events_screen.dart';

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
    PluginsScreen(
      onModelChanged: (pluginName, modelPath) async {
        // Global update logic or notify
        debugPrint("Global model updated for $pluginName: $modelPath");
      },
    ),
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
