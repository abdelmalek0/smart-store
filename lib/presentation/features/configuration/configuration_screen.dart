import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_store_linux/application/di/injection_container.dart';
import 'package:smart_store_linux/application/blocs/configuration/configuration_bloc.dart';
import 'package:smart_store_linux/application/blocs/configuration/configuration_event.dart';
import 'package:smart_store_linux/application/blocs/configuration/configuration_state.dart';
import 'package:smart_store_linux/presentation/common/utils/theme/app_theme.dart';
import 'package:smart_store_linux/presentation/common/widgets/modern/modern_widgets.dart';

class ConfigurationScreen extends StatelessWidget {
  const ConfigurationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ConfigurationBloc>(
      create: (_) => sl<ConfigurationBloc>()..add(const ConfigurationLoaded()),
      child: BlocBuilder<ConfigurationBloc, ConfigurationState>(
        builder: (context, state) {
          return Column(
            children: [
              const ModernHeader(
                title: "Configuration",
                subtitle: "Map streams to plugins",
              ),
              const SizedBox(height: 20),
              Expanded(
                child: state.streams.isEmpty
                    ? Center(
                        child: ModernLabel(
                          "No streams available. Go to Streams to add one.",
                          color: AppTheme.text.withValues(alpha: 0.5),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        itemCount: state.streams.length,
                        itemBuilder: (context, index) {
                          final stream = state.streams[index];
                          final activePluginId = stream.activePluginId;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF111827),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFF1F2937),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1F2937),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.settings_input_component,
                                        color: Color(0xFF60A5FA),
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(
                                        stream.name,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1F2937),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        "ID: ${stream.id.substring(0, 4)}...",
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 11,
                                          color: Color(0xFF6B7280),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                Row(
                                  children: [
                                    const Text(
                                      "Active Plugin:",
                                      style: TextStyle(
                                        color: Color(0xFF9CA3AF),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0F172A),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFF334155),
                                          ),
                                        ),
                                        child: DropdownButtonHideUnderline(
                                          child: DropdownButton<String>(
                                            value:
                                                state.plugins.any(
                                                  (p) => p.id == activePluginId,
                                                )
                                                ? activePluginId
                                                : null,
                                            isExpanded: true,
                                            dropdownColor: const Color(
                                              0xFF1E293B,
                                            ),
                                            hint: const Text(
                                              "None",
                                              style: TextStyle(
                                                color: Color(0xFF64748B),
                                                fontSize: 13,
                                              ),
                                            ),
                                            icon: const Icon(
                                              Icons.keyboard_arrow_down,
                                              color: Color(0xFF94A3B8),
                                            ),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                            ),
                                            items: [
                                              const DropdownMenuItem<String>(
                                                value: null,
                                                child: Text("None"),
                                              ),
                                              ...state.plugins.map((plugin) {
                                                return DropdownMenuItem<String>(
                                                  value: plugin.id,
                                                  child: Text(
                                                    plugin.name,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                );
                                              }),
                                            ],
                                            onChanged: (value) {
                                              context
                                                  .read<ConfigurationBloc>()
                                                  .add(
                                                    ConfigurationPluginSet(
                                                      streamId: stream.id,
                                                      pluginId: value,
                                                    ),
                                                  );
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
