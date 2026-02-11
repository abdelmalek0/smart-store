import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_store_linux/ui/utils/theme/app_theme.dart';
import 'package:smart_store_linux/ui/providers/model_provider.dart';
import 'package:smart_store_linux/ui/widgets/modern_widgets.dart';
import 'package:smart_store_linux/core/models/model_info.dart';
import 'package:smart_store_linux/ui/widgets/dialogs/models_dialogs.dart';
import 'package:smart_store_linux/ui/viewModels/models_viewmodel.dart';

class ModelsScreen extends StatelessWidget {
  const ModelsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final modelProvider = Provider.of<ModelProvider>(context);

    return ChangeNotifierProvider(
      create: (_) => ModelsViewModel(modelProvider: modelProvider),
      child: Consumer<ModelsViewModel>(
        builder: (context, vm, _) {
          return Column(
            children: [
              ModernHeader(
                title: "Models",
                subtitle: "Manage ONNX models",
                actions: [
                  ModernButton(
                    label: "Add Model",
                    icon: Icons.add,
                    onPressed: () => showAddModelDialog(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: vm.models.isEmpty
                    ? _buildEmptyState(context)
                    : ListView.builder(
                        itemCount: vm.models.length,
                        itemBuilder: (context, index) {
                          final model = vm.models[index];
                          return _buildModelCard(context, model, modelProvider);
                        },
                      ),
              ),
            ],
          );
        },
      ),
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
                    showUploadLabelsDialog(context, model, provider),
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
            onPressed: () => showAddModelDialog(context),
          ),
        ],
      ),
    );
  }
}
