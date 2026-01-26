import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_store_linux/ui/theme/app_theme.dart';
import 'package:smart_store_linux/ui/providers/rtsp_stream_provider.dart';
import 'package:smart_store_linux/ui/providers/model_provider.dart';
import 'package:smart_store_linux/ui/providers/inference_provider.dart';
import 'package:smart_store_linux/ui/widgets/modern_widgets.dart';
import 'package:smart_store_linux/ui/widgets/detached_stream_player.dart';
import 'package:smart_store_linux/backend/streaming/pipeline/stream_manager.dart';
import 'package:smart_store_linux/ui/widgets/live/camera_sidebar.dart';

class PlaybackScreen extends StatefulWidget {
  const PlaybackScreen({super.key});

  @override
  State<PlaybackScreen> createState() => _PlaybackScreenState();
}

class _PlaybackScreenState extends State<PlaybackScreen> {
  String? _selectedStreamId;
  bool _isSidebarOpen = true;

  @override
  Widget build(BuildContext context) {
    return Consumer4<
      RTSPStreamProvider,
      InferenceProvider,
      ModelProvider,
      StreamProcessManager
    >(
      builder:
          (
            context,
            streamProvider,
            inferenceProvider,
            modelProvider,
            processManager,
            child,
          ) {
            if (streamProvider.streams.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.videocam_off,
                      size: 60,
                      color: AppTheme.text,
                    ),
                    const SizedBox(height: 16),
                    ModernLabel(
                      "No streams available.",
                      color: AppTheme.text.withOpacity(0.5),
                      fontSize: 18,
                    ),
                  ],
                ),
              );
            }

            // Auto-select first stream if none selected
            if (_selectedStreamId == null &&
                streamProvider.streams.isNotEmpty) {
              // Schedule microtask to avoid setState during build if needed,
              // but for local state init it's often okay or better handled in initState.
              // Used local var init logic here for simplicity.
              _selectedStreamId = streamProvider.streams.first.id;
            }

            final selectedStream = streamProvider.streams.firstWhere(
              (s) => s.id == _selectedStreamId,
              orElse: () => streamProvider.streams.first,
            );

            return Row(
              children: [
                // Collapsible Sidebar
                CameraSidebar(
                  streams: streamProvider.streams,
                  selectedStreamId: _selectedStreamId,
                  onStreamSelected: (id) =>
                      setState(() => _selectedStreamId = id),
                  isOpen: _isSidebarOpen,
                  processManager: processManager,
                ),

                // Main Content Area
                Expanded(
                  child: Container(
                    color: const Color(
                      0xFF0F1218,
                    ), // Main background (Darker than sidebar)
                    child: Column(
                      children: [
                        // Top Header Bar
                        Container(
                          height: 60,
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: Color(0xFF1E293B),
                              ), // Slate-800
                            ),
                          ),
                          child: Row(
                            children: [
                              // Live Status Indicator
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444), // Red-500
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFFEF4444,
                                      ).withOpacity(0.5),
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

                              // Expand Button (Toggle Sidebar)
                              _buildHeaderButton(
                                _isSidebarOpen
                                    ? Icons.fullscreen
                                    : Icons.fullscreen_exit,
                                _isSidebarOpen ? "Expand" : "Collapse",
                                () {
                                  setState(() {
                                    _isSidebarOpen = !_isSidebarOpen;
                                  });
                                },
                                highlight: true,
                              ),
                            ],
                          ),
                        ),

                        // Video Player Area
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                // Resolve Model Path
                                String? modelPath;
                                final modelId = inferenceProvider
                                    .getModelForStream(selectedStream.id);
                                if (modelId != null) {
                                  try {
                                    final modelInfo = modelProvider.models
                                        .firstWhere((m) => m.id == modelId);
                                    modelPath = modelInfo.path;
                                  } catch (_) {}
                                }

                                return Center(
                                  child: AspectRatio(
                                    aspectRatio:
                                        16 /
                                        9, // Enforce 16:9 for cinematic look
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black,
                                        borderRadius: BorderRadius.circular(8),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(
                                              0.5,
                                            ),
                                            blurRadius: 20,
                                            offset: const Offset(0, 10),
                                          ),
                                        ],
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: DetachedStreamPlayer(
                                        key: ValueKey(selectedStream.id),
                                        url: selectedStream.url,
                                        streamId: selectedStream.id,
                                        label: selectedStream.name,
                                        modelPath: modelPath,
                                      ),
                                    ),
                                  ),
                                );
                              },
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
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool highlight = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: highlight
              ? const Color(0xFF3B82F6)
              : Colors.transparent, // Blue or Transparent
          border: highlight
              ? null
              : Border.all(color: const Color(0xFF334155)), // Slate-700
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
                color: highlight
                    ? Colors.white
                    : const Color(0xFF94A3B8), // Slate-400
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
