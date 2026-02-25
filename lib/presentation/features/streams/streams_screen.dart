import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_store_linux/domain/entities/config/stream_config.dart';
import 'package:smart_store_linux/application/di/injection_container.dart';
import 'package:smart_store_linux/application/blocs/streams/streams_bloc.dart';
import 'package:smart_store_linux/application/blocs/streams/streams_event.dart';
import 'package:smart_store_linux/application/blocs/streams/streams_state.dart';
import 'package:smart_store_linux/presentation/common/utils/theme/app_theme.dart';
import 'package:smart_store_linux/presentation/common/widgets/modern/modern_widgets.dart';
import 'package:smart_store_linux/presentation/common/widgets/dialogs/stream_dialogs.dart';

class StreamsScreen extends StatelessWidget {
  const StreamsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<StreamsBloc>(
      create: (_) => sl<StreamsBloc>()..add(const StreamsLoaded()),
      child: Builder(
        builder: (context) => Column(
          children: [
            ModernHeader(
              title: "Streams",
              subtitle: "Manage RTSP streams",
              actions: [
                ModernButton(
                  label: "Add Stream",
                  icon: Icons.add,
                  onPressed: () => showAddStreamDialog(context),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: BlocBuilder<StreamsBloc, StreamsState>(
                builder: (context, state) {
                  if (state.streams.isEmpty) {
                    return _buildEmptyState(context);
                  }
                  return ListView.builder(
                    itemCount: state.streams.length,
                    itemBuilder: (context, index) {
                      return _buildCameraCard(context, state.streams[index]);
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

  Widget _buildCameraCard(BuildContext context, StreamConfig stream) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: Row(
        children: [
          Container(
            width: 80,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(8),
              image: const DecorationImage(
                image: NetworkImage("https://placeholder.com/150"),
                fit: BoxFit.cover,
                opacity: 0.6,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stream.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1F2937),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        stream.url,
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.settings, color: Color(0xFF94A3B8)),
                onPressed: () {},
                tooltip: "Settings",
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: Color(0xFFEF4444),
                ),
                onPressed: () =>
                    context.read<StreamsBloc>().add(StreamRemoved(stream.id)),
                tooltip: "Remove Camera",
              ),
            ],
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
            Icons.videocam_off_outlined,
            size: 64,
            color: AppTheme.text.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),
          ModernLabel(
            "No cameras connected",
            color: AppTheme.text.withValues(alpha: 0.5),
            fontSize: 16,
          ),
          const SizedBox(height: 24),
          ModernButton(
            label: "Add your first stream",
            icon: Icons.add,
            onPressed: () => showAddStreamDialog(context),
          ),
        ],
      ),
    );
  }
}
