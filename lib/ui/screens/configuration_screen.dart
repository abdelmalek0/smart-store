import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_store_linux/core/plugins/plugin_registry.dart';
import 'package:smart_store_linux/ui/utils/theme/app_theme.dart';
import 'package:smart_store_linux/ui/providers/rtsp_stream_provider.dart';
import 'package:smart_store_linux/ui/widgets/modern_widgets.dart';
import 'package:smart_store_linux/ui/viewModels/configuration_viewmodel.dart';

class ConfigurationScreen extends StatefulWidget {
  const ConfigurationScreen({super.key});

  @override
  State<ConfigurationScreen> createState() => _ConfigurationScreenState();
}

class _ConfigurationScreenState extends State<ConfigurationScreen> {
  @override
  Widget build(BuildContext context) {
    final streamProvider = Provider.of<RTSPStreamProvider>(context);
    final vm = ConfigurationViewModel(streamProvider: streamProvider);

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
                    color: AppTheme.text.withValues(alpha: 0.5),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: streamProvider.streams.length,
                  itemBuilder: (context, index) {
                    final stream = streamProvider.streams[index];

                    // Fetch Active Plugin for this stream via ViewModel
                    final activePluginId = vm.getActivePlugin(stream.id);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(
                          0xFF111827,
                        ), // Dark slate/black card bg
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF1F2937)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1F2937),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.settings_input_component,
                                  color: Color(0xFF60A5FA),
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  stream.name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1F2937),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  "ID: ${stream.id.substring(0, 4)}...",
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    color: Color(0xFF6B7280),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          Row(
                            children: [
                              const Text(
                                "Active Plugin:",
                                style: TextStyle(
                                  color: Color(0xFF9CA3AF),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF0F172A,
                                    ), // Darker input bg
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFF334155),
                                    ),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value:
                                          PluginRegistry.plugins.any(
                                            (p) => p.id == activePluginId,
                                          )
                                          ? activePluginId
                                          : null, // Default to null (None)
                                      isExpanded: true,
                                      dropdownColor: const Color(0xFF1E293B),
                                      hint: const Text(
                                        "None",
                                        style: TextStyle(
                                          color: Color(0xFF64748B),
                                          fontSize: 13,
                                        ),
                                      ),
                                      icon: const Icon(
                                        Icons.keyboard_arrow_down,
                                        color: Color(0xFF94A3B8),
                                      ),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                      ),
                                      items: [
                                        const DropdownMenuItem<String>(
                                          value: null,
                                          child: Text("None"),
                                        ),
                                        ...PluginRegistry.plugins.map((plugin) {
                                          return DropdownMenuItem<String>(
                                            value: plugin.id,
                                            child: Text(
                                              plugin.name,
                                              style: const TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                          );
                                        }),
                                      ],
                                      onChanged: (value) async {
                                        await vm.setActivePlugin(
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
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
