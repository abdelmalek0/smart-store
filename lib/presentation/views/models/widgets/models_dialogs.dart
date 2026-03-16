import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import 'package:smart_store_linux/presentation/common/utils/theme/app_theme.dart';
import 'package:smart_store_linux/presentation/common/widgets/modern/modern_widgets.dart';
import 'package:smart_store_linux/domain/entities/config/model_config.dart';
import 'package:smart_store_linux/domain/utils/label_parser.dart';
import 'package:smart_store_linux/application/blocs/models/models_bloc.dart';
import 'package:smart_store_linux/application/blocs/models/models_event.dart';

/// Dialog helpers extracted from ModelsScreen for single-responsibility.
///
/// Platform-specific code preserved:
///   - Android: manual path entry for model files (.rknn) and labels (.txt)
///   - Linux/Desktop: uses FilePicker for both

/// Show the "Add Model" dialog. Dispatches [ModelFileAdded] to [ModelsBloc].
void showAddModelDialog(BuildContext context) {
  String? selectedPath;
  // Android-only: which format the user is adding (RKNN vs TFLite).
  bool isRknn = true;
  final bloc = context.read<ModelsBloc>();

  showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final ext = isRknn ? '.rknn' : '.tflite';
        final hint = isRknn
            ? '/sdcard/Download/model.rknn'
            : '/sdcard/Download/model.tflite';

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
              // ── Android: format selector ──────────────────────────────
              if (Platform.isAndroid) ...[
                const ModernLabel(
                  'Model Format',
                  fontSize: 13,
                  color: Colors.white70,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('RKNN'),
                      selected: isRknn,
                      onSelected: (_) => setState(() {
                        isRknn = true;
                        selectedPath = null;
                      }),
                      selectedColor:
                          AppTheme.accent.withValues(alpha: 0.22),
                      labelStyle: TextStyle(
                        color: isRknn
                            ? AppTheme.accent
                            : Colors.white54,
                        fontWeight: isRknn
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('TFLite'),
                      selected: !isRknn,
                      onSelected: (_) => setState(() {
                        isRknn = false;
                        selectedPath = null;
                      }),
                      selectedColor:
                          AppTheme.accent.withValues(alpha: 0.22),
                      labelStyle: TextStyle(
                        color: !isRknn
                            ? AppTheme.accent
                            : Colors.white54,
                        fontWeight: !isRknn
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              // ── File picker button ────────────────────────────────────
              ModernButton(
                label: Platform.isAndroid
                    ? 'Pick $ext File'
                    : 'Pick .onnx File',
                icon: Icons.folder_open,
                onPressed: () async {
                  if (Platform.isAndroid) {
                    final controller = TextEditingController();
                    final String? path = await showDialog<String>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: AppTheme.surface,
                        title: ModernLabel(
                          'Enter ${isRknn ? 'RKNN' : 'TFLite'} Model Path',
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ModernLabel(
                              'Enter the full path to your $ext file:',
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: controller,
                              decoration: InputDecoration(
                                hintText: hint,
                                hintStyle:
                                    const TextStyle(color: Colors.white38),
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
                      if (!path.toLowerCase().endsWith(ext)) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('File must have $ext extension'),
                            backgroundColor: AppTheme.destructive,
                          ),
                        );
                      } else {
                        final exists = await file.exists();
                        if (!exists) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('File not found at path'),
                              backgroundColor: AppTheme.destructive,
                            ),
                          );
                        } else {
                          setState(() => selectedPath = path);
                        }
                      }
                    }
                  } else {
                    try {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['onnx'],
                      );
                      if (result != null &&
                          result.files.single.path != null) {
                        setState(
                            () => selectedPath = result.files.single.path);
                      }
                    } catch (e) {
                      debugPrint('Error picking file: $e');
                    }
                  }
                },
              ),
              const SizedBox(height: 16),
              // ── Selected path preview ─────────────────────────────────
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
                        'Selected File:',
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
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: selectedPath != null
                  ? () {
                      bloc.add(ModelFileAdded(selectedPath!));
                      Navigator.pop(context);
                    }
                  : null,
              child: Text(
                'Add',
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

/// Show the "Upload Labels" dialog for a model.
void showUploadLabelsDialog(BuildContext context, ModelConfig model) {
  final bloc = context.read<ModelsBloc>();

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
          if (model.labels.isNotEmpty)
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
                    "${model.labels.length} custom labels loaded",
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
        if (model.labels.isNotEmpty)
          TextButton(
            onPressed: () {
              bloc.add(ModelLabelsUpdated(modelId: model.id, labels: {}));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Custom labels removed'),
                  backgroundColor: Color(0xFF6B7280),
                ),
              );
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
          onPressed: () => _pickAndUploadLabels(context, model, bloc),
          child: const Text(
            "Upload File",
            style: TextStyle(color: AppTheme.accent),
          ),
        ),
      ],
    ),
  );
}

Future<void> _pickAndUploadLabels(
  BuildContext context,
  ModelConfig model,
  ModelsBloc bloc,
) async {
  Navigator.pop(context);

  if (Platform.isAndroid) {
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
      if (!context.mounted) return;
      await _processLabelsFile(context, path, model, bloc);
    }
  } else {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt'],
      );
      if (result != null && result.files.single.path != null) {
        if (!context.mounted) return;
        await _processLabelsFile(
          context,
          result.files.single.path!,
          model,
          bloc,
        );
      }
    } catch (e) {
      debugPrint("Error picking file: $e");
    }
  }
}

Future<void> _processLabelsFile(
  BuildContext context,
  String path,
  ModelConfig model,
  ModelsBloc bloc,
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

    bloc.add(ModelLabelsUpdated(modelId: model.id, labels: labels));

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
