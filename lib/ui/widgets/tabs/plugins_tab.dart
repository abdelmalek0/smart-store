import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_store_linux/backend/services/config_service.dart';
import 'package:smart_store_linux/ui/providers/model_provider.dart';
import 'package:smart_store_linux/ui/widgets/modern_widgets.dart';

class PluginsTab extends StatefulWidget {
  final Function(String, String) onModelChanged;

  const PluginsTab({super.key, required this.onModelChanged});

  @override
  State<PluginsTab> createState() => _PluginsTabState();
}

class _PluginsTabState extends State<PluginsTab> {
  // Available Plugin Definitions
  final List<Map<String, dynamic>> _availablePlugins = [
    {
      'id': 'people_counting',
      'name': 'People Counting',
      'description': 'Initializes YOLO model to count people.',
      'isActive': true,
    },
    {
      'id': 'coming_soon',
      'name': 'Heatmap (Coming Soon)',
      'description': 'Visualizes dwell time and movement.',
      'isActive': false,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer<ModelProvider>(
      builder: (context, modelProvider, child) {
        return Column(
          children: [
            const ModernHeader(
              title: "Plugins",
              subtitle: "Manage system capabilities",
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: _availablePlugins.length,
                itemBuilder: (context, index) {
                  final plugin = _availablePlugins[index];
                  return _buildPluginCard(plugin, modelProvider);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPluginCard(
    Map<String, dynamic> plugin,
    ModelProvider modelProvider,
  ) {
    final name = plugin['name'] as String;
    final description = plugin['description'] as String;
    final pluginId = plugin['id'] as String;
    final isEnabled = plugin['isActive'] as bool;

    // Load persisted GLOBAL model for this plugin
    String? currentModelPath;
    final config = ConfigService.instance.getGlobalPluginConfig(pluginId);
    if (config != null && config.containsKey('modelPath')) {
      currentModelPath = config['modelPath'];
    }

    // Fallback default
    if (currentModelPath == null && modelProvider.models.isNotEmpty) {
      currentModelPath = modelProvider.models.first.path;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF111827), // Dark slate/black card bg
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2937),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isEnabled ? Icons.extension : Icons.construction,
                  color: isEnabled ? const Color(0xFF3B82F6) : Colors.grey,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (isEnabled)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF064E3B).withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF065F46)),
                  ),
                  child: const Text(
                    "Active",
                    style: TextStyle(
                      color: Color(0xFF34D399),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),

          if (isEnabled && pluginId == 'people_counting') ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1F2937).withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF374151)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Default Model Configuration",
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Color(0xFFD1D5DB),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (modelProvider.models.isEmpty)
                    Row(
                      children: [
                        const Icon(
                          Icons.warning_amber,
                          color: Color(0xFFF59E0B),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          "No AI models available.",
                          style: TextStyle(
                            color: Color(0xFFF59E0B),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111827),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF4B5563)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: currentModelPath,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF1F2937),
                          icon: const Icon(
                            Icons.keyboard_arrow_down,
                            color: Color(0xFF9CA3AF),
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                          items: modelProvider.models.map((model) {
                            return DropdownMenuItem<String>(
                              value: model.path,
                              child: Text(
                                model.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (value) async {
                            if (value != null) {
                              setState(() {}); // Update UI

                              // 1. Persist Global Defaults
                              await ConfigService.instance
                                  .setGlobalPluginConfig(pluginId, {
                                    'modelPath': value,
                                    'personClassId': 0,
                                    'confidenceThreshold': 0.5,
                                  });

                              // 2. Notify Parent/System
                              widget.onModelChanged(name, value);
                            }
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
