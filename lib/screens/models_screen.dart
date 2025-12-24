import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:smart_store_linux/theme/app_theme.dart';
import 'package:smart_store_linux/providers/model_provider.dart';
import 'package:smart_store_linux/widgets/modern_widgets.dart';

class ModelsScreen extends StatelessWidget {
  const ModelsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final modelProvider = Provider.of<ModelProvider>(context);

    return Column(
      children: [
        ModernHeader(
          title: "Models",
          subtitle: "Manage ONNX models",
          actions: [
            ModernButton(
              label: "Add Model",
              icon: Icons.add,
              onPressed: () => _showAddModelDialog(context),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Expanded(
          child: modelProvider.models.isEmpty
              ? Center(
                  child: ModernLabel(
                    "No models added yet.",
                    color: AppTheme.text.withValues(alpha: 0.5),
                  ),
                )
              : ListView.builder(
                  itemCount: modelProvider.models.length,
                  itemBuilder: (context, index) {
                    final model = modelProvider.models[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ModernCard(
                        child: Row(
                          children: [
                            Icon(Icons.extension, color: AppTheme.accent),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ModernLabel(
                                    model.name,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  const SizedBox(height: 4),
                                  ModernLabel(
                                    model.path,
                                    fontSize: 12,
                                    color: AppTheme.text.withValues(alpha: 0.6),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete,
                                color: AppTheme.destructive,
                              ),
                              onPressed: () =>
                                  modelProvider.removeModel(model.id),
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

  void _showAddModelDialog(BuildContext context) {
    String? selectedPath;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: AppTheme.surface,
            title: const ModernLabel(
              "Add Model",
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ModernButton(
                  label: "Pick .onnx File",
                  icon: Icons.folder_open,
                  onPressed: () async {
                    try {
                      FilePickerResult? result = await FilePicker.platform
                          .pickFiles(
                            type: FileType.custom,
                            allowedExtensions: ['onnx'],
                          );

                      if (result != null && result.files.single.path != null) {
                        setState(() {
                          selectedPath = result.files.single.path;
                        });
                      }
                    } catch (e) {
                      debugPrint("Error picking file: $e");
                    }
                  },
                ),
                const SizedBox(height: 16),
                if (selectedPath != null)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Selected File:",
                          style: TextStyle(color: Colors.grey, fontSize: 10),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          selectedPath!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                child: const Text("Cancel"),
                onPressed: () => Navigator.pop(context),
              ),
              TextButton(
                onPressed: selectedPath != null
                    ? () {
                        Provider.of<ModelProvider>(
                          context,
                          listen: false,
                        ).addModel(selectedPath!);
                        Navigator.pop(context);
                      }
                    : null,
                child: Text(
                  "Add",
                  style: TextStyle(
                    color: selectedPath != null
                        ? AppTheme.accent
                        : Colors.white24,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
