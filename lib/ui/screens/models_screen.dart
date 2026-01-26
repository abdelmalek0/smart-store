import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:smart_store_linux/ui/theme/app_theme.dart';
import 'package:smart_store_linux/ui/providers/model_provider.dart';
import 'package:smart_store_linux/ui/widgets/modern_widgets.dart';

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
              ? _buildEmptyState(context)
              : ListView.builder(
                  itemCount: modelProvider.models.length,
                  itemBuilder: (context, index) {
                    final model = modelProvider.models[index];
                    return _buildModelCard(context, model, modelProvider);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildModelCard(BuildContext context, model, ModelProvider provider) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827), // Dark slate/black card bg
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1F2937),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.extension, color: Color(0xFF818CF8)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  model.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  model.path,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
            onPressed: () => provider.removeModel(model.id),
            tooltip: "Remove Model",
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.extension_off_outlined,
            size: 64,
            color: AppTheme.text.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),
          ModernLabel(
            "No AI models loaded",
            color: AppTheme.text.withValues(alpha: 0.5),
            fontSize: 16,
          ),
          const SizedBox(height: 24),
          ModernButton(
            label: "Add your first model",
            icon: Icons.add,
            onPressed: () => _showAddModelDialog(context),
          ),
        ],
      ),
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
                    if (Platform.isAndroid) {
                      // Android: Manual path entry (scoped storage workaround)
                      final controller = TextEditingController();
                      final String? path = await showDialog<String>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: AppTheme.surface,
                          title: const ModernLabel(
                            'Enter Model Path',
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const ModernLabel(
                                'Enter the full path to your .rknn file:',
                                fontSize: 12,
                                color: Colors.white70,
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: controller,
                                decoration: const InputDecoration(
                                  hintText: '/sdcard/Download/model.rknn',
                                  hintStyle: TextStyle(color: Colors.white38),
                                ),
                                style: const TextStyle(color: Colors.white),
                                autofocus: true,
                              ),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const ModernLabel('Cancel'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(ctx, controller.text.trim()),
                              child: const ModernLabel(
                                'OK',
                                color: AppTheme.accent,
                              ),
                            ),
                          ],
                        ),
                      );

                      if (path != null && path.isNotEmpty) {
                        final file = File(path);
                        if (!path.toLowerCase().endsWith('.rknn')) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('File must have .rknn extension'),
                              backgroundColor: AppTheme.destructive,
                            ),
                          );
                        } else if (!await file.exists()) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('File not found at path'),
                              backgroundColor: AppTheme.destructive,
                            ),
                          );
                        } else {
                          setState(() {
                            selectedPath = path;
                          });
                        }
                      }
                    } else {
                      // Desktop: Use file picker
                      try {
                        FilePickerResult? result = await FilePicker.platform
                            .pickFiles(
                              type: FileType.custom,
                              allowedExtensions: ['onnx'],
                            );
                        if (result != null &&
                            result.files.single.path != null) {
                          setState(() {
                            selectedPath = result.files.single.path;
                          });
                        }
                      } catch (e) {
                        debugPrint("Error picking file: $e");
                      }
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
