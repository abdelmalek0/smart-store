import 'package:flutter/material.dart';
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
                    color: AppTheme.text.withOpacity(0.5),
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
                                  ModernLabel(model.name, fontWeight: FontWeight.bold),
                                  const SizedBox(height: 4),
                                  ModernLabel(
                                    model.path,
                                    fontSize: 12,
                                    color: AppTheme.text.withOpacity(0.6),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: AppTheme.destructive),
                              onPressed: () => modelProvider.removeModel(model.id),
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
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const ModernLabel("Add Model", fontSize: 18, fontWeight: FontWeight.bold),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ModernInput(
              hint: "/path/to/model.onnx",
              controller: controller,
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text("Add", style: TextStyle(color: AppTheme.accent)),
            onPressed: () {
              if (controller.text.isNotEmpty) {
                Provider.of<ModelProvider>(context, listen: false).addModel(controller.text);
                Navigator.pop(context);
              }
            },
          ),
        ],
      ),
    );
  }
}
