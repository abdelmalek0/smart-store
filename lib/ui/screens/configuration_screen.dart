import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_store_linux/ui/theme/app_theme.dart';
import 'package:smart_store_linux/ui/providers/rtsp_stream_provider.dart';
import 'package:smart_store_linux/ui/widgets/modern_widgets.dart';
import 'package:smart_store_linux/backend/services/config_service.dart';

class ConfigurationScreen extends StatefulWidget {
  const ConfigurationScreen({super.key});

  @override
  State<ConfigurationScreen> createState() => _ConfigurationScreenState();
}

class _ConfigurationScreenState extends State<ConfigurationScreen> {
  // Hardcoded available plugins (should match PluginsTab ideally, or come from a registry)
  final List<Map<String, String>> _availablePlugins = [
    {'id': 'people_counting', 'name': 'People Counting'},
    {'id': 'coming_soon', 'name': 'Heatmap (Coming Soon)'},
  ];

  @override
  Widget build(BuildContext context) {
    final streamProvider = Provider.of<RTSPStreamProvider>(context);

    // Force rebuild to fetch latest config if needed?
    // Ideally we listen to a ConfigProvider, but setState on interaction works for now.

    return Column(
      children: [
        const ModernHeader(
          title: "Configuration",
          subtitle: "Map streams to plugins",
        ),
        const SizedBox(height: 20),
        Expanded(
          child: streamProvider.streams.isEmpty
              ? Center(
                  child: ModernLabel(
                    "No streams available. Go to Streams to add one.",
                    color: AppTheme.text.withOpacity(0.5),
                  ),
                )
              : ListView.builder(
                  itemCount: streamProvider.streams.length,
                  itemBuilder: (context, index) {
                    final stream = streamProvider.streams[index];

                    // Fetch Active Plugin for this stream
                    final activePluginId = ConfigService.instance
                        .getStreamActivePlugin(stream.id);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ModernCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.settings_input_component,
                                  color: AppTheme.primary,
                                ),
                                const SizedBox(width: 12),
                                ModernLabel(
                                  stream.name,
                                  fontWeight: FontWeight.bold,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            ModernLabel(
                              "Active Plugin:",
                              fontSize: 12,
                              color: AppTheme.text.withOpacity(0.7),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.background,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppTheme.surface),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value:
                                      _availablePlugins.any(
                                        (p) => p['id'] == activePluginId,
                                      )
                                      ? activePluginId
                                      : null, // Default to null (None)
                                  isExpanded: true,
                                  dropdownColor: AppTheme.surface,
                                  hint: Text(
                                    "None",
                                    style: TextStyle(
                                      color: AppTheme.text.withOpacity(0.5),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.arrow_drop_down,
                                    color: AppTheme.text,
                                  ),
                                  style: const TextStyle(color: AppTheme.text),
                                  items: [
                                    const DropdownMenuItem<String>(
                                      value: null,
                                      child: Text("None"),
                                    ),
                                    ..._availablePlugins.map((plugin) {
                                      final isEnabled =
                                          plugin['id'] != 'coming_soon';
                                      return DropdownMenuItem<String>(
                                        value: plugin['id'],
                                        enabled: isEnabled,
                                        child: Text(
                                          plugin['name']!,
                                          style: TextStyle(
                                            color: isEnabled
                                                ? Colors.white
                                                : Colors.grey,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ],
                                  onChanged: (value) async {
                                    await ConfigService.instance
                                        .setStreamActivePlugin(
                                          stream.id,
                                          value,
                                        );
                                    setState(
                                      () {},
                                    ); // Rebuild to show selection
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
