import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_store_linux/core/config/config_service.dart';
import 'package:smart_store_linux/core/models/plugin_info.dart';
import 'package:smart_store_linux/core/plugins/plugin_registry.dart';
import 'package:smart_store_linux/ui/providers/model_provider.dart';
import 'package:smart_store_linux/ui/widgets/modern_widgets.dart';
import 'package:smart_store_linux/ui/viewModels/plugins_viewmodel.dart';

class PluginsTab extends StatefulWidget {
  final Function(String, String) onModelChanged;

  const PluginsTab({super.key, required this.onModelChanged});

  @override
  State<PluginsTab> createState() => _PluginsTabState();
}

class _PluginsTabState extends State<PluginsTab> {
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
                itemCount: PluginRegistry.plugins.length,
                itemBuilder: (context, index) {
                  final plugin = PluginRegistry.plugins[index];
                  return _buildPluginCard(plugin, modelProvider);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPluginCard(PluginInfo plugin, ModelProvider modelProvider) {
    final name = plugin.name;
    final description = plugin.description;
    final pluginId = plugin.id;
    final isEnabled = plugin.isActive;

    // Load persisted GLOBAL model via ViewModel pattern
    final vm = PluginsViewModel(modelProvider: modelProvider);
    final currentModelPath = vm.getModelPathForPlugin(pluginId);

    // Fallback default - REMOVED per user request
    // if (currentModelPath == null && modelProvider.models.isNotEmpty) {
    //   currentModelPath = modelProvider.models.first.path;
    // }

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
                  plugin.icon,
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

          if (isEnabled &&
              (pluginId == 'people_counting' ||
                  pluginId == 'kitchen_supervision')) ...[
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
                        child: DropdownButton<String?>(
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
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text(
                                "None",
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                            ...modelProvider.models.map((model) {
                              return DropdownMenuItem<String?>(
                                value: model.path,
                                child: Text(
                                  model.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }),
                          ],
                          onChanged: (value) async {
                            setState(() {}); // Update UI

                            if (value != null) {
                              // 1. Persist Global Defaults
                              final Map<String, dynamic> newConfig = {
                                'modelPath': value,
                              };

                              if (pluginId == 'people_counting') {
                                newConfig['personClassId'] = 0;
                                newConfig['confidenceThreshold'] = 0.5;
                              } else if (pluginId == 'kitchen_supervision') {
                                newConfig['handClassId'] = 4; // 'no-gloves'
                                newConfig['confidenceThreshold'] = 0.5;
                              }

                              await ConfigService.instance
                                  .setGlobalPluginConfig(pluginId, newConfig);

                              // 2. Notify Parent/System
                              widget.onModelChanged(name, value);
                            } else {
                              // Clear configuration
                              final existingConfig =
                                  ConfigService.instance.getGlobalPluginConfig(
                                    pluginId,
                                  ) ??
                                  {};
                              existingConfig.remove('modelPath');
                              await ConfigService.instance
                                  .setGlobalPluginConfig(
                                    pluginId,
                                    existingConfig,
                                  );
                              widget.onModelChanged(name, "None");
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
