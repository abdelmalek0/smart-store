import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_store_linux/ui/utils/theme/app_theme.dart';
import 'package:smart_store_linux/ui/providers/app_provider.dart';
import 'package:smart_store_linux/ui/widgets/sidebar.dart';
import 'package:smart_store_linux/ui/screens/dashboard_screen.dart';
import 'package:smart_store_linux/ui/screens/models_screen.dart';
import 'package:smart_store_linux/ui/screens/streams_screen.dart';
import 'package:smart_store_linux/ui/screens/configuration_screen.dart';

import 'package:smart_store_linux/ui/screens/playback_screen.dart';
import 'package:smart_store_linux/ui/widgets/tabs/plugins_tab.dart';
import 'package:smart_store_linux/ui/widgets/tabs/events_tab.dart';

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
    PluginsTab(
      onModelChanged: (pluginName, modelPath) async {
        // Global update logic or notify
        debugPrint("Global model updated for $pluginName: $modelPath");
      },
    ),
    const ConfigurationScreen(),
    const PlaybackScreen(),
    const EventsTab(),
  ];

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);

    return Scaffold(
      body: Row(
        children: [
          Sidebar(
            selectedIndex: _selectedIndex,
            onItemSelected: (index) => setState(() => _selectedIndex = index),
            isExpanded: appProvider.isSidebarExpanded,
            onToggle: appProvider.toggleSidebar,
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
