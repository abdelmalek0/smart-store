import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_store_linux/ui/providers/app_provider.dart';
import 'package:smart_store_linux/ui/providers/rtsp_stream_provider.dart';
import 'package:smart_store_linux/ui/widgets/modern_widgets.dart';
import 'package:smart_store_linux/backend/streaming/pipeline/stream_manager.dart';
import 'package:smart_store_linux/ui/providers/inference_provider.dart';
import 'package:smart_store_linux/ui/providers/model_provider.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);
    final streamProvider = Provider.of<RTSPStreamProvider>(context);
    final inferenceProvider = Provider.of<InferenceProvider>(
      context,
      listen: false,
    );
    final modelProvider = Provider.of<ModelProvider>(context, listen: false);

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
                // 2. Main Content Grid
                LayoutBuilder(
                  builder: (context, constraints) {
                    // Responsive layout: Row on wide screens, Column on narrow
                    if (constraints.maxWidth > 900) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: _buildSystemHealthCard(appProvider),
                          ),
                        ],
                      );
                    } else {
                      return Column(
                        children: [_buildSystemHealthCard(appProvider)],
                      );
                    }
                  },
                ),
                const SizedBox(height: 10),
                // 1. Top Stats Row
                _buildStatsRow(
                  context,
                  appProvider,
                  streamProvider,
                  inferenceProvider,
                  modelProvider,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(
    BuildContext context,
    AppProvider appProvider,
    RTSPStreamProvider streamProvider,
    InferenceProvider inferenceProvider,
    ModelProvider modelProvider,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 3 items per row on wide, spacing 16. Total spacing = 16 * 2 = 32.
        final cardWidth = (constraints.maxWidth - 32) / 3;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _buildStatCard(
              title: "Cameras",
              value: "${streamProvider.streams.length}",
              icon: Icons.videocam,
              color: Colors.blueAccent,
              width: cardWidth,
            ),
            _buildStatCard(
              title: "AI Models",
              value: "${modelProvider.models.length}",
              icon: Icons.extension,
              color: Colors.purpleAccent,
              width: cardWidth,
            ),
            _buildStatCard(
              title: "Plugins",
              value: "2",
              icon: Icons.layers,
              color: Colors.orangeAccent,
              width: cardWidth,
            ),
            _buildControlCard(
              context,
              appProvider,
              streamProvider,
              inferenceProvider,
              modelProvider,
              width: cardWidth,
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required double width,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Icon(icon, color: color, size: 18),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlCard(
    BuildContext context,
    AppProvider appProvider,
    RTSPStreamProvider streamProvider,
    InferenceProvider inferenceProvider,
    ModelProvider modelProvider, {
    required double width,
  }) {
    final isRunning = appProvider.isEngineRunning;
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
            onTap: () async {
              final shouldRun = !appProvider.isEngineRunning;
              appProvider.toggleEngine();
              if (shouldRun) {
                StreamProcessManager.instance.startAll(
                  streamProvider.streams,
                  inferenceProvider.streamModelMap,
                  modelProvider.models,
                );
              } else {
                await StreamProcessManager.instance.stopAll();
              }
            },
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

  Widget _buildSystemHealthCard(AppProvider appProvider) {
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
            appProvider.cpuName,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          _buildResourceBar(
            "CPU Usage",
            "${appProvider.stats['cpu']?.toStringAsFixed(1)}%",
            appProvider.stats['cpu'] ?? 0,
            Colors.blueAccent,
          ),
          const SizedBox(height: 15),

          // RAM
          _buildResourceBar(
            "RAM Usage",
            "${appProvider.stats['ram']?.toStringAsFixed(1)} / ${appProvider.ramTotal.toStringAsFixed(1)} GB",
            appProvider.ramTotal > 0
                ? ((appProvider.stats['ram'] ?? 0) / appProvider.ramTotal) * 100
                : 0,
            Colors.orangeAccent,
          ),
          const SizedBox(height: 15),

          // GPU
          Text(
            appProvider.gpuName,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          _buildResourceBar(
            "GPU Usage",
            "${appProvider.stats['gpu']?.toStringAsFixed(1)}%",
            appProvider.stats['gpu'] ?? 0,
            Colors.greenAccent,
          ),
          const SizedBox(height: 15),

          // VRAM
          _buildResourceBar(
            "VRAM",
            "${appProvider.vramUsage.toStringAsFixed(1)} / ${appProvider.vramTotal.toStringAsFixed(1)} GB",
            appProvider.vramTotal > 0
                ? (appProvider.vramUsage / appProvider.vramTotal) * 100
                : 0,
            Colors.purpleAccent,
          ),
        ],
      ),
    );
  }

  Widget _buildResourceBar(
    String label,
    String detail,
    double percentage,
    Color color,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
            ),
            Text(
              detail,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Stack(
          children: [
            Container(
              height: 8,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF374151),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            FractionallySizedBox(
              widthFactor: (percentage / 100).clamp(0.0, 1.0),
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.5),
                      blurRadius: 6,
                      spreadRadius: 0,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
