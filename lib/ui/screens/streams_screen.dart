import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_store_linux/ui/theme/app_theme.dart';
import 'package:smart_store_linux/ui/providers/rtsp_stream_provider.dart';
import 'package:smart_store_linux/ui/widgets/modern_widgets.dart';

class StreamsScreen extends StatelessWidget {
  const StreamsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final streamProvider = Provider.of<RTSPStreamProvider>(context);

    return Column(
      children: [
        ModernHeader(
          title: "Streams",
          subtitle: "Manage RTSP streams",
          actions: [
            ModernButton(
              label: "Add Stream",
              icon: Icons.add,
              onPressed: () => _showAddStreamDialog(context),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Expanded(
          child: streamProvider.streams.isEmpty
              ? Center(
                  child: ModernLabel(
                    "No streams added yet.",
                    color: AppTheme.text.withOpacity(0.5),
                  ),
                )
              : ListView.builder(
                  itemCount: streamProvider.streams.length,
                  itemBuilder: (context, index) {
                    final stream = streamProvider.streams[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ModernCard(
                        child: Row(
                          children: [
                            Icon(Icons.videocam, color: AppTheme.primary),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ModernLabel(
                                    stream.name,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  const SizedBox(height: 4),
                                  ModernLabel(
                                    stream.url,
                                    fontSize: 12,
                                    color: AppTheme.text.withOpacity(0.6),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete,
                                color: AppTheme.destructive,
                              ),
                              onPressed: () =>
                                  streamProvider.removeStream(stream.id),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showAddStreamDialog(BuildContext context) {
    final urlController = TextEditingController();
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const ModernLabel(
          "Add RTSP Stream",
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ModernInput(
              hint: "Stream Name (Optional)",
              controller: nameController,
            ),
            const SizedBox(height: 12),
            ModernInput(hint: "rtsp://...", controller: urlController),
          ],
        ),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(
            child: const Text("Add", style: TextStyle(color: AppTheme.accent)),
            onPressed: () {
              if (urlController.text.isNotEmpty) {
                Provider.of<RTSPStreamProvider>(
                  context,
                  listen: false,
                ).addStream(
                  urlController.text,
                  name: nameController.text.isNotEmpty
                      ? nameController.text
                      : null,
                );
                Navigator.pop(context);
              }
            },
          ),
        ],
      ),
    );
  }
}
