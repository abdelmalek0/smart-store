import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:smart_store_linux/ui/theme/app_theme.dart';
import 'package:smart_store_linux/ui/providers/model_provider.dart';
import 'package:smart_store_linux/ui/widgets/modern_widgets.dart';
import 'package:smart_store_linux/core/models/model_info.dart';
import 'package:smart_store_linux/core/utils/label_parser.dart';

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

  Widget _buildModelCard(
    BuildContext context,
    ModelInfo model,
    ModelProvider provider,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main row: icon, name/path, actions
          Row(
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            model.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Custom Labels Badge
                        if (model.hasCustomLabels) ...[
                          const SizedBox(width: 8),
                          _buildLabelsBadge(model.customLabels!.length),
                        ],
                      ],
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
              // Upload Labels Button
              IconButton(
                icon: Icon(
                  model.hasCustomLabels ? Icons.label : Icons.label_outline,
                  color: model.hasCustomLabels
                      ? const Color(0xFF10B981) // Green when active
                      : const Color(0xFF6B7280),
                ),
                onPressed: () =>
                    _showUploadLabelsDialog(context, model, provider),
                tooltip: model.hasCustomLabels
                    ? "Custom Labels (${model.customLabels!.length} classes)"
                    : "Upload Labels",
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: Color(0xFFEF4444),
                ),
                onPressed: () => provider.removeModel(model.id),
                tooltip: "Remove Model",
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Badge showing custom labels are active
  Widget _buildLabelsBadge(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.label, size: 12, color: Color(0xFF10B981)),
          const SizedBox(width: 4),
          Text(
            "$count labels",
            style: const TextStyle(
              color: Color(0xFF10B981),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Dialog to upload custom labels from .txt file
  void _showUploadLabelsDialog(
    BuildContext context,
    ModelInfo model,
    ModelProvider provider,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const ModernLabel(
          "Custom Labels",
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ModernLabel(
              "Upload a .txt file with one class name per line:",
              fontSize: 12,
              color: Colors.white70,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                "person\ncar\ntruck\nbicycle",
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Current status
            if (model.hasCustomLabels)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: const Color(0xFF10B981).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      size: 16,
                      color: Color(0xFF10B981),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "${model.customLabels!.length} custom labels loaded",
                      style: const TextStyle(
                        color: Color(0xFF10B981),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          if (model.hasCustomLabels)
            TextButton(
              onPressed: () async {
                await provider.updateModelLabels(model.id, null);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Custom labels removed'),
                      backgroundColor: Color(0xFF6B7280),
                    ),
                  );
                }
              },
              child: const Text(
                "Clear Labels",
                style: TextStyle(color: Color(0xFFEF4444)),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => _pickAndUploadLabels(context, model, provider),
            child: const Text(
              "Upload File",
              style: TextStyle(color: AppTheme.accent),
            ),
          ),
        ],
      ),
    );
  }

  /// Pick and parse a labels file
  Future<void> _pickAndUploadLabels(
    BuildContext context,
    ModelInfo model,
    ModelProvider provider,
  ) async {
    Navigator.pop(context); // Close dialog first

    if (Platform.isAndroid) {
      // Android: Manual path entry (scoped storage workaround)
      final controller = TextEditingController();
      final String? path = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const ModernLabel(
            'Enter Labels File Path',
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ModernLabel(
                'Enter the full path to your .txt labels file:',
                fontSize: 12,
                color: Colors.white70,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: '/sdcard/Download/labels.txt',
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
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const ModernLabel('OK', color: AppTheme.accent),
            ),
          ],
        ),
      );

      if (path != null && path.isNotEmpty) {
        await _processLabelsFile(context, path, model, provider);
      }
    } else {
      // Desktop: Use file picker
      try {
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['txt'],
        );
        if (result != null && result.files.single.path != null) {
          await _processLabelsFile(
            context,
            result.files.single.path!,
            model,
            provider,
          );
        }
      } catch (e) {
        debugPrint("Error picking file: $e");
      }
    }
  }

  /// Process and save labels from file
  Future<void> _processLabelsFile(
    BuildContext context,
    String path,
    ModelInfo model,
    ModelProvider provider,
  ) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('File not found at path'),
              backgroundColor: AppTheme.destructive,
            ),
          );
        }
        return;
      }

      final content = await file.readAsString();
      final labels = parseLabelsFromContent(content);

      if (labels.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No labels found in file'),
              backgroundColor: AppTheme.destructive,
            ),
          );
        }
        return;
      }

      debugPrint("[LABELS UPLOAD] Model ID: ${model.id}, Path: ${model.path}");
      debugPrint("[LABELS UPLOAD] Parsed ${labels.length} labels: $labels");
      await provider.updateModelLabels(model.id, labels);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Loaded ${labels.length} custom labels'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error reading file: $e'),
            backgroundColor: AppTheme.destructive,
          ),
        );
      }
    }
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
