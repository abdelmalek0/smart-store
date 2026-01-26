import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_store_linux/backend/services/config_service.dart';
import 'package:smart_store_linux/ui/providers/model_provider.dart';

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
        return Container(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Plugin Definitions",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Configure global default settings for plugins. Active selection is done in Configuration.",
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: _availablePlugins.length,
                  itemBuilder: (context, index) {
                    final plugin = _availablePlugins[index];
                    return _buildPluginCard(plugin, modelProvider);
                  },
                ),
              ),
            ],
          ),
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

    return Card(
      color: Colors.grey[900],
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.extension, color: Colors.blueAccent),
                const SizedBox(width: 8),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(description, style: TextStyle(color: Colors.grey[400])),
            if (isEnabled && pluginId == 'people_counting') ...[
              const SizedBox(height: 16),
              const Text(
                "Default Model Configuration",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 8),
              if (modelProvider.models.isEmpty)
                const Text(
                  "No models available to select.",
                  style: TextStyle(color: Colors.orange),
                )
              else
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: "Default Model",
                    border: OutlineInputBorder(),
                    fillColor: Colors.black26,
                    filled: true,
                  ),
                  dropdownColor: Colors.grey[900],
                  value: currentModelPath,
                  style: const TextStyle(color: Colors.white),
                  items: modelProvider.models.map((model) {
                    return DropdownMenuItem<String>(
                      value: model.path,
                      child: Text(model.name, overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                  onChanged: (value) async {
                    if (value != null) {
                      setState(() {
                        // Update local state implicitly
                      });

                      // 1. Persist Global Defaults
                      await ConfigService.instance
                          .setGlobalPluginConfig(pluginId, {
                            'modelPath': value,
                            'personClassId': 0,
                            'confidenceThreshold': 0.5,
                          });

                      // 2. Notify Parent/System (Might need restart to take effect on existing streams?)
                      widget.onModelChanged(name, value);
                    }
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }
}
