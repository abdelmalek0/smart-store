import 'package:flutter/material.dart';
import 'package:smart_store_linux/core/config/config_service.dart';
import 'package:smart_store_linux/core/plugins/models/plugin_info.dart';
import 'package:smart_store_linux/ui/viewModels/plugins_viewmodel.dart';

class PluginCard extends StatefulWidget {
  final PluginInfo plugin;
  final PluginsViewModel vm;
  final Function(String, String) onModelChanged;

  const PluginCard({
    super.key,
    required this.plugin,
    required this.vm,
    required this.onModelChanged,
  });

  @override
  State<PluginCard> createState() => _PluginCardState();
}

class _PluginCardState extends State<PluginCard> {
  @override
  Widget build(BuildContext context) {
    final name = widget.plugin.name;
    final description = widget.plugin.description;
    final pluginId = widget.plugin.id;
    final isEnabled = widget.plugin.isActive;

    final vm = widget.vm;
    final currentModelPath = vm.getModelPathForPlugin(pluginId);
    debugPrint("PluginCard: Building $pluginId. ModelPath: $currentModelPath");
    final models = ConfigService.instance.models;

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
                  widget.plugin.icon,
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
                  if (models.isEmpty)
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
                            ...models.map((model) {
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
                            // setState(() {}); // Not needed, VM notification will rebuild parent Consumer
                            // Actually, DropdownButton is inside this widget which is NOT a Consumer,
                            // but the parent PluginCardState build method reads from 'vm'
                            // and 'ConfigService.instance.models'.
                            // However, PluginCard is rebuilt by Parent Consumer when VM notifies.
                            // So we just need to call the VM.

                            if (value != null) {
                              await vm.setModelForPlugin(pluginId, value);
                              widget.onModelChanged(name, value);
                            } else {
                              await vm.setModelForPlugin(pluginId, null);
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
