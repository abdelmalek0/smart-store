import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_store_linux/theme/app_theme.dart';
import 'package:smart_store_linux/providers/rtsp_stream_provider.dart';
import 'package:smart_store_linux/providers/model_provider.dart';
import 'package:smart_store_linux/providers/inference_provider.dart';
import 'package:smart_store_linux/widgets/modern_widgets.dart';
import 'package:smart_store_linux/widgets/detached_stream_player.dart';

class PlaybackScreen extends StatefulWidget {
  const PlaybackScreen({super.key});

  @override
  State<PlaybackScreen> createState() => _PlaybackScreenState();
}

class _PlaybackScreenState extends State<PlaybackScreen> {
  String? _selectedStreamId;

  @override
  Widget build(BuildContext context) {
    return Consumer3<RTSPStreamProvider, InferenceProvider, ModelProvider>(
      builder: (context, streamProvider, inferenceProvider, modelProvider, child) {
        if (streamProvider.streams.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.videocam_off, size: 60, color: AppTheme.text),
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

        return Row(
          children: [
            // Stream Switcher (Left Side)
            Container(
              width: 250,
              decoration: BoxDecoration(
                color: AppTheme.surface,
                border: const Border(right: BorderSide(color: AppTheme.border)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: ModernLabel("Cameras", fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: streamProvider.streams.length,
                      itemBuilder: (context, index) {
                        final stream = streamProvider.streams[index];
                        final isSelected = _selectedStreamId == stream.id;
                        return ListTile(
                          title: Text(stream.name, style: const TextStyle(color: Colors.white)),
                          subtitle: Text(stream.url, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10)),
                          selected: isSelected,
                          selectedTileColor: AppTheme.primary.withOpacity(0.2),
                          onTap: () {
                            setState(() {
                              _selectedStreamId = stream.id;
                            });
                          },
                          leading: Icon(Icons.videocam, color: isSelected ? AppTheme.accent : Colors.white54),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            
            // Main Player Area (Right Side)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: _selectedStreamId == null
                    ? const Center(child: Text("Select a camera to view feed", style: TextStyle(color: Colors.white54)))
                    : Builder(
                        key: ValueKey(_selectedStreamId), // Rebuild when stream changes
                        builder: (context) {
                          final stream = streamProvider.streams.firstWhere((s) => s.id == _selectedStreamId);
                          
                          // Resolve Model Path
                          String? modelPath;
                          final modelId = inferenceProvider.getModelForStream(stream.id);
                          if (modelId != null) {
                            try {
                              final modelInfo = modelProvider.models.firstWhere((m) => m.id == modelId);
                              modelPath = modelInfo.path;
                            } catch (_) {}
                          }

                          return DetachedStreamPlayer(
                            url: stream.url,
                            label: stream.name,
                            modelPath: modelPath,
                          );
                        },
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}
