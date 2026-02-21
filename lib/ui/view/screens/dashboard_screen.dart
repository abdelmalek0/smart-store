import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_store_linux/core/di/injection_container.dart';
import 'package:smart_store_linux/presentation/blocs/dashboard/dashboard_bloc.dart';
import 'package:smart_store_linux/presentation/blocs/dashboard/dashboard_event.dart';
import 'package:smart_store_linux/presentation/blocs/dashboard/dashboard_state.dart';
import 'package:smart_store_linux/ui/view/widgets/modern/modern_widgets.dart';
import 'package:smart_store_linux/ui/view/widgets/cards/stat_card.dart';
import 'package:smart_store_linux/ui/view/widgets/cards/resource_bar.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<DashboardBloc>(
      create: (_) => sl<DashboardBloc>()..add(const DashboardStarted()),
      child: const _DashboardContent(),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DashboardBloc, DashboardState>(
      builder: (context, state) {
        return SingleChildScrollView(
          child: Column(
            children: [
              const ModernHeader(
                title: "System Dashboard",
                subtitle: "Global Overview & Health",
              ),
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth > 900) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 2,
                                child: _HealthCard(state: state),
                              ),
                            ],
                          );
                        } else {
                          return Column(children: [_HealthCard(state: state)]);
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    _buildStatsRow(context, state),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatsRow(BuildContext context, DashboardState state) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 32) / 3;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            StatCard(
              title: "Cameras",
              value: "${state.cameraCount}",
              icon: Icons.videocam,
              color: Colors.blueAccent,
              width: cardWidth,
            ),
            StatCard(
              title: "AI Models",
              value: "${state.modelCount}",
              icon: Icons.extension,
              color: Colors.purpleAccent,
              width: cardWidth,
            ),
            StatCard(
              title: "Plugins",
              value: "${state.pluginCount}",
              icon: Icons.layers,
              color: Colors.orangeAccent,
              width: cardWidth,
            ),
            _ControlCard(state: state, width: cardWidth),
          ],
        );
      },
    );
  }
}

class _HealthCard extends StatelessWidget {
  final DashboardState state;

  const _HealthCard({required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "System Health",
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          // CPU
          Text(
            state.cpuName,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          ResourceBar(
            label: "CPU Usage",
            detail: "${state.stats['cpu']?.toStringAsFixed(1)}%",
            percentage: state.stats['cpu'] ?? 0,
            color: Colors.blueAccent,
          ),
          const SizedBox(height: 15),
          // RAM
          ResourceBar(
            label: "RAM Usage",
            detail:
                "${state.stats['ram']?.toStringAsFixed(1)} / ${state.ramTotal.toStringAsFixed(1)} GB",
            percentage: state.ramTotal > 0
                ? ((state.stats['ram'] ?? 0) / state.ramTotal) * 100
                : 0,
            color: Colors.orangeAccent,
          ),
          const SizedBox(height: 15),
          // GPU
          Text(
            state.gpuName,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          ResourceBar(
            label: state.supportsVRAM ? "GPU Usage" : "NPU Usage",
            detail: "${state.stats['gpu']?.toStringAsFixed(1)}%",
            percentage: state.stats['gpu'] ?? 0,
            color: Colors.greenAccent,
          ),
          if (state.supportsVRAM) ...[
            const SizedBox(height: 15),
            ResourceBar(
              label: "VRAM",
              detail:
                  "${state.vramUsage.toStringAsFixed(1)} / ${state.vramTotal.toStringAsFixed(1)} GB",
              percentage: state.vramTotal > 0
                  ? (state.vramUsage / state.vramTotal) * 100
                  : 0,
              color: Colors.purpleAccent,
            ),
          ],
        ],
      ),
    );
  }
}

class _ControlCard extends StatelessWidget {
  final DashboardState state;
  final double width;

  const _ControlCard({required this.state, required this.width});

  @override
  Widget build(BuildContext context) {
    final isRunning = state.isEngineRunning;
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isRunning
              ? [const Color(0xFF064E3B), const Color(0xFF065F46)]
              : [const Color(0xFF1F2937), const Color(0xFF111827)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isRunning ? const Color(0xFF059669) : const Color(0xFF374151),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Engine Status",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isRunning ? const Color(0xFF34D399) : Colors.red,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (isRunning ? const Color(0xFF34D399) : Colors.red)
                          .withValues(alpha: 0.6),
                      blurRadius: 4,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () => context.read<DashboardBloc>().add(
              const DashboardEngineToggleRequested(),
            ),
            child: Row(
              children: [
                Text(
                  isRunning ? "RUNNING" : "STOPPED",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Icon(
                  isRunning
                      ? Icons.stop_circle_outlined
                      : Icons.play_circle_outline,
                  color: Colors.white,
                  size: 20,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
