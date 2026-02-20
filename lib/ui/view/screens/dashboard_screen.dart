import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_store_linux/core/services/app/app_service.dart';
import 'package:smart_store_linux/ui/view/widgets/modern/modern_widgets.dart';
import 'package:smart_store_linux/ui/view/widgets/cards/stat_card.dart';
import 'package:smart_store_linux/ui/viewModels/dashboard_viewmodel.dart';
import 'package:smart_store_linux/ui/view/widgets/cards/resource_bar.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DashboardViewModel(AppService.instance),
      child: const _DashboardContent(),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent();

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardViewModel>(
      builder: (context, vm, _) {
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
                              Expanded(flex: 2, child: const _HealthCard()),
                            ],
                          );
                        } else {
                          return const Column(children: [_HealthCard()]);
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    // 1. Top Stats Row
                    _buildStatsRow(context, vm),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatsRow(BuildContext context, DashboardViewModel vm) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 3 items per row on wide, spacing 16. Total spacing = 16 * 2 = 32.
        final cardWidth = (constraints.maxWidth - 32) / 3;

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            StatCard(
              title: "Cameras",
              value: "${vm.cameraCount}",
              icon: Icons.videocam,
              color: Colors.blueAccent,
              width: cardWidth,
            ),
            StatCard(
              title: "AI Models",
              value: "${vm.modelCount}",
              icon: Icons.extension,
              color: Colors.purpleAccent,
              width: cardWidth,
            ),
            StatCard(
              title: "Plugins",
              value: "${vm.pluginCount}",
              icon: Icons.layers,
              color: Colors.orangeAccent,
              width: cardWidth,
            ),
            _ControlCard(vm: vm, width: cardWidth),
          ],
        );
      },
    );
  }
}

class _HealthCard extends StatelessWidget {
  const _HealthCard();

  @override
  Widget build(BuildContext context) {
    // Listen to AppService for updates
    // Note: We access AppService global instance here for simplicity in this pure view widget,
    // or we could pass data via ViewModel if we want strict purity.
    // Given the pattern, using AppService.instance here for *data binding* in a dumb widget is okay,
    // OR we should be getting these stats from the ViewModel.
    // The previous implementation used AppService.instance directly.
    // To be strictly MVVM/DI specific, we should probably access these via the ViewModel or pass them in.
    // However, the ViewModel "stats" getter delegates to AppService anyway.
    // Let's stick to using ViewModel data if possible, or Consumer.

    // Better: Consumer<DashboardViewModel> is already above.
    // But _HealthCard is static content structure, data comes from... AppService.instance directly in original code.
    // Let's keep it as is for now to minimize risk, but access via AppService.instance is still a direct dependency.
    // Ideally ViewModel should expose a 'systemStats' object we can listen to.
    // But ViewModel notifies listeners when AppService updates.

    return Consumer<DashboardViewModel>(
      builder: (context, vm, _) {
        // We can access properties through VM since it wraps AppService properties
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
                vm.cpuName,
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
                detail: "${vm.stats['cpu']?.toStringAsFixed(1)}%",
                percentage: vm.stats['cpu'] ?? 0,
                color: Colors.blueAccent,
              ),
              const SizedBox(height: 15),

              // RAM
              ResourceBar(
                label: "RAM Usage",
                detail:
                    "${vm.stats['ram']?.toStringAsFixed(1)} / ${vm.ramTotal.toStringAsFixed(1)} GB",
                percentage: vm.ramTotal > 0
                    ? ((vm.stats['ram'] ?? 0) / vm.ramTotal) * 100
                    : 0,
                color: Colors.orangeAccent,
              ),
              const SizedBox(height: 15),

              // GPU
              Text(
                vm.gpuName,
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
                label: vm.supportsVRAM ? "GPU Usage" : "NPU Usage",
                detail: "${vm.stats['gpu']?.toStringAsFixed(1)}%",
                percentage: vm.stats['gpu'] ?? 0,
                color: Colors.greenAccent,
              ),
              if (vm.supportsVRAM) ...[
                const SizedBox(height: 15),

                // VRAM
                ResourceBar(
                  label: "VRAM",
                  detail:
                      "${vm.vramUsage.toStringAsFixed(1)} / ${vm.vramTotal.toStringAsFixed(1)} GB",
                  percentage: vm.vramTotal > 0
                      ? (vm.vramUsage / vm.vramTotal) * 100
                      : 0,
                  color: Colors.purpleAccent,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ControlCard extends StatelessWidget {
  final DashboardViewModel vm;
  final double width;

  const _ControlCard({required this.vm, required this.width});

  @override
  Widget build(BuildContext context) {
    final isRunning = vm.isEngineRunning;
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
            onTap: () => vm.toggleEngine(),
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
