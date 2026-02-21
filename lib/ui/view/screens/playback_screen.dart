import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_store_linux/services/config_service.dart';
import 'package:smart_store_linux/core/di/injection_container.dart';
import 'package:smart_store_linux/features/engine/engine_orchestrator.dart';
import 'package:smart_store_linux/presentation/blocs/playback/playback_bloc.dart';
import 'package:smart_store_linux/presentation/blocs/playback/playback_event.dart';
import 'package:smart_store_linux/presentation/blocs/playback/playback_state.dart';
import 'package:smart_store_linux/ui/utils/theme/app_theme.dart';
import 'package:smart_store_linux/ui/view/widgets/modern/modern_widgets.dart';
import 'package:smart_store_linux/ui/view/widgets/media/detached_stream_player.dart';
import 'package:smart_store_linux/ui/view/widgets/navigation/camera_sidebar.dart';

class PlaybackScreen extends StatelessWidget {
  const PlaybackScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<PlaybackBloc>(
      create: (_) => sl<PlaybackBloc>(),
      child: const _PlaybackContent(),
    );
  }
}

class _PlaybackContent extends StatelessWidget {
  const _PlaybackContent();

  @override
  Widget build(BuildContext context) {
    final streams = ConfigService.instance.streams;

    if (streams.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.videocam_off, size: 60, color: AppTheme.text),
            const SizedBox(height: 16),
            ModernLabel(
              "No streams available.",
              color: AppTheme.text.withValues(alpha: 0.5),
              fontSize: 18,
            ),
          ],
        ),
      );
    }

    // Auto-select first stream if none selected
    if (streams.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<PlaybackBloc>().add(
          PlaybackFirstAutoSelected(streams.first.id),
        );
      });
    }

    return BlocBuilder<PlaybackBloc, PlaybackState>(
      builder: (context, state) {
        final selectedId = state.selectedStreamId ?? streams.first.id;
        final selectedStream = streams.firstWhere(
          (s) => s.id == selectedId,
          orElse: () => streams.first,
        );

        return Row(
          children: [
            CameraSidebar(
              streams: streams,
              selectedStreamId: selectedId,
              onStreamSelected: (id) =>
                  context.read<PlaybackBloc>().add(PlaybackStreamSelected(id)),
              isOpen: state.isSidebarOpen,
              processManager: EngineOrchestrator.instance,
            ),
            Expanded(
              child: Container(
                color: const Color(0xFF0F1218),
                child: Column(
                  children: [
                    Container(
                      height: 60,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Color(0xFF1E293B)),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFFEF4444,
                                  ).withValues(alpha: 0.5),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            "Live Feed: ${selectedStream.name}",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const Spacer(),
                          _buildHeaderButton(
                            context,
                            state.isSidebarOpen
                                ? Icons.fullscreen
                                : Icons.fullscreen_exit,
                            state.isSidebarOpen ? "Expand" : "Collapse",
                            highlight: true,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: DetachedStreamPlayer(
                                key: ValueKey(selectedStream.id),
                                streamId: selectedStream.id,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeaderButton(
    BuildContext context,
    IconData icon,
    String label, {
    bool highlight = false,
  }) {
    return InkWell(
      onTap: () =>
          context.read<PlaybackBloc>().add(const PlaybackSidebarToggled()),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: highlight ? const Color(0xFF3B82F6) : Colors.transparent,
          border: highlight ? null : Border.all(color: const Color(0xFF334155)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: highlight ? Colors.white : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: highlight ? Colors.white : const Color(0xFF94A3B8),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
