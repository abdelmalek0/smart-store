import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_store_linux/domain/entities/plugin_entity.dart';
import 'package:smart_store_linux/presentation/blocs/plugins/plugins_bloc.dart';
import 'package:smart_store_linux/presentation/blocs/plugins/plugins_event.dart';
import 'package:smart_store_linux/presentation/blocs/plugins/plugins_state.dart';
import 'package:smart_store_linux/ui/utils/plugin_catalog.dart';

class PluginCard extends StatelessWidget {
  final PluginEntity plugin;

  const PluginCard({super.key, required this.plugin});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PluginsBloc, PluginsState>(
      builder: (context, state) {
        final pluginId = plugin.id;
        final name = plugin.name;
        final description = plugin.description;
        final isEnabled = plugin.isActive;
        final models = state.availableModels;

        // Derive current model path from ConfigService via bloc state
        String? currentModelPath;

        // Get the current model path for this plugin by reading from the state
        // The PluginsBloc exposes configService — we call a method to get it
        // Instead, we'll build a helper inside the state that computes this
        // Since state has availableModels, we can't easily get the assigned model path without calling service
        // Use a workaround: call the BLoC's configService through the BLoC itself
        // We'll use a stateless approach and have the BLoC expose a getter:
        final bloc = context.read<PluginsBloc>();
        currentModelPath = bloc.getModelPathForPlugin(pluginId);

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
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
                      PluginCatalog.iconFor(plugin.iconName),
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
                        const Row(
                          children: [
                            Icon(
                              Icons.warning_amber,
                              color: Color(0xFFF59E0B),
                              size: 16,
                            ),
                            SizedBox(width: 8),
                            Text(
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
                              onChanged: (value) {
                                context.read<PluginsBloc>().add(
                                  PluginModelSet(
                                    pluginId: pluginId,
                                    modelPath: value,
                                  ),
                                );
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
      },
    );
  }
}
