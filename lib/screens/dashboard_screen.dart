import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_store_linux/theme/app_theme.dart';
import 'package:smart_store_linux/providers/app_provider.dart';
import 'package:smart_store_linux/providers/rtsp_stream_provider.dart';
import 'package:smart_store_linux/widgets/modern_widgets.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appProvider = Provider.of<AppProvider>(context);
    final streamProvider = Provider.of<RTSPStreamProvider>(context);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              const ModernHeader(
                title: "Dashboard",
                subtitle: "System overview and controls",
              ),
              const SizedBox(height: 20),
              // System Monitoring (2-line format)
              ModernCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ModernLabel(
                      "System Monitoring",
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Note: Metrics are system-wide (app-specific monitoring not available)",
                      style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.text.withOpacity(0.5),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Line 1: CPU
                    Row(
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text(
                            "CPU",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.blueAccent,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            appProvider.cpuName,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.text.withOpacity(0.8),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(
                          width: 80,
                          child: Text(
                            "${appProvider.stats['cpu']?.toStringAsFixed(1)}%",
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.blueAccent,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 100,
                          child: Text(
                            "${appProvider.stats['ram']?.toStringAsFixed(1)} GB RAM",
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.text.withOpacity(0.7),
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Line 2: GPU
                    Row(
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text(
                            "GPU",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.purpleAccent,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            appProvider.gpuName,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.text.withOpacity(0.8),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(
                          width: 80,
                          child: Text(
                            "${appProvider.stats['gpu']?.toStringAsFixed(1)}%",
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.purpleAccent,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 100,
                          child: Text(
                            "${appProvider.vramUsage.toStringAsFixed(1)} / ${appProvider.vramTotal.toStringAsFixed(1)} GB",
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.text.withOpacity(0.7),
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
        // Main Controls
        SliverFillRemaining(
          hasScrollBody: false,
          child: ModernCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ModernLabel(
                  "Engine Controls",
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                const SizedBox(height: 20),
                ModernButton(
                  label: appProvider.isEngineRunning ? "Stop Engine" : "Start Engine",
                  isDestructive: appProvider.isEngineRunning,
                  onPressed: appProvider.toggleEngine,
                  icon: appProvider.isEngineRunning ? Icons.stop : Icons.play_arrow,
                ),
                const SizedBox(height: 20),
                Divider(color: Colors.white.withOpacity(0.1)),
                const SizedBox(height: 10),
                _buildStatusRow("Active Streams", "${streamProvider.streams.length}"),
                _buildStatusRow("Engine Status", appProvider.isEngineRunning ? "Running" : "Stopped"),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, String subtitle, Color color) {
    return ModernCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ModernLabel(title, color: AppTheme.text.withOpacity(0.7)),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.text.withOpacity(0.5),
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ModernLabel(label),
          ModernLabel(value, fontWeight: FontWeight.bold, color: AppTheme.primary),
        ],
      ),
    );
  }
}
