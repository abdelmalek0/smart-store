import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_store_linux/theme/app_theme.dart';
import 'package:smart_store_linux/providers/rtsp_stream_provider.dart';
import 'package:smart_store_linux/providers/model_provider.dart';
import 'package:smart_store_linux/providers/inference_provider.dart';
import 'package:smart_store_linux/widgets/modern_widgets.dart';

class ConfigurationScreen extends StatelessWidget {
  const ConfigurationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final streamProvider = Provider.of<RTSPStreamProvider>(context);
    final modelProvider = Provider.of<ModelProvider>(context);
    final inferenceProvider = Provider.of<InferenceProvider>(context);

    return Column(
      children: [
        const ModernHeader(
          title: "Configuration",
          subtitle: "Map streams to detection models",
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
                    final selectedModelId = inferenceProvider.getModelForStream(
                      stream.id,
                    );

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
                              "Select Model:",
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
                                      modelProvider.models.any(
                                        (m) => m.id == selectedModelId,
                                      )
                                      ? selectedModelId
                                      : null,
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
                                    ...modelProvider.models.map((model) {
                                      return DropdownMenuItem<String>(
                                        value: model.id,
                                        child: Text(model.name),
                                      );
                                    }).toList(),
                                  ],
                                  onChanged: (value) {
                                    if (value == null) {
                                      inferenceProvider.setModelForStream(
                                        stream.id,
                                        null,
                                        null,
                                      );
                                    } else {
                                      try {
                                        final model = modelProvider.models
                                            .firstWhere((m) => m.id == value);
                                        inferenceProvider.setModelForStream(
                                          stream.id,
                                          value,
                                          model.path,
                                        );
                                      } catch (e) {
                                        debugPrint("Error selecting model: $e");
                                      }
                                    }
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
