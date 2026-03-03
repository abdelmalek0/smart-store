import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_store_linux/domain/entities/config/model_config.dart';
import 'package:smart_store_linux/application/di/injection_container.dart';
import 'package:smart_store_linux/application/blocs/models/models_bloc.dart';
import 'package:smart_store_linux/application/blocs/models/models_event.dart';
import 'package:smart_store_linux/application/blocs/models/models_state.dart';
import 'package:smart_store_linux/presentation/common/utils/theme/app_theme.dart';
import 'package:smart_store_linux/presentation/common/widgets/modern/modern_widgets.dart';
import 'package:smart_store_linux/presentation/views/models/widgets/models_dialogs.dart';

class ModelsScreen extends StatelessWidget {
  const ModelsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ModelsBloc>(
      create: (_) => sl<ModelsBloc>()..add(const ModelsLoaded()),
      child: Builder(
        builder: (context) => Column(
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
              child: BlocBuilder<ModelsBloc, ModelsState>(
                builder: (context, state) {
                  if (state.models.isEmpty) {
                    return _buildEmptyState(context);
                  }
                  return ListView.builder(
                    itemCount: state.models.length,
                    itemBuilder: (context, index) {
                      return _buildModelCard(context, state.models[index]);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelCard(BuildContext context, ModelConfig model) {
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
                        if (model.labels.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          _buildLabelsBadge(model.labels.length),
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
              IconButton(
                icon: Icon(
                  model.labels.isNotEmpty ? Icons.label : Icons.label_outline,
                  color: model.labels.isNotEmpty
                      ? const Color(0xFF10B981)
                      : const Color(0xFF6B7280),
                ),
                onPressed: () => showUploadLabelsDialog(context, model),
                tooltip: model.labels.isNotEmpty
                    ? "Custom Labels (${model.labels.length} classes)"
                    : "Upload Labels",
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: Color(0xFFEF4444),
                ),
                onPressed: () =>
                    context.read<ModelsBloc>().add(ModelRemoved(model.id)),
                tooltip: "Remove Model",
              ),
            ],
          ),
        ],
      ),
    );
  }

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
