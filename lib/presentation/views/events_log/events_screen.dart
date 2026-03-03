import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_store_linux/domain/repositories/i_config_repository.dart';
import 'package:smart_store_linux/application/di/injection_container.dart';
import 'package:smart_store_linux/application/blocs/events_log/events_log_bloc.dart';
import 'package:smart_store_linux/application/blocs/events_log/events_log_event.dart';
import 'package:smart_store_linux/application/blocs/events_log/events_log_state.dart';
import 'package:smart_store_linux/presentation/views/events_log/widgets/event_card.dart';

class EventsScreen extends StatelessWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // EventsLogBloc is a singleton in the DI container so history persists.
    return BlocProvider<EventsLogBloc>.value(
      value: sl<EventsLogBloc>()..add(const EventsLogStarted()),
      child: const _EventsContent(),
    );
  }
}

class _EventsContent extends StatelessWidget {
  const _EventsContent();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<EventsLogBloc, EventsLogState>(
      builder: (context, state) {
        return Container(
          color: const Color(0xFF111722),
          child: Column(
            children: [
              const SizedBox(height: 16),
              Expanded(
                child: state.events.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.notifications_off_outlined,
                              size: 48,
                              color: Colors.grey[700],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              "No recent alerts",
                              style: TextStyle(color: Colors.grey[700]),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: state.events.length,
                        itemBuilder: (context, index) {
                          final event = state.events[index];
                          final streamConfig = sl<IConfigRepository>().getStream(
                            event.streamId,
                          );
                          final streamName =
                              streamConfig?.name ?? event.streamId;
                          return EventCard(
                            event: event,
                            streamName: streamName,
                          );
                        },
                      ),
              ),
              if (state.events.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () => context.read<EventsLogBloc>().add(
                          const EventsLogCleared(),
                        ),
                        child: const Text(
                          "Clear All",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: TextButton(
                  onPressed: () {},
                  child: const Text(
                    "View Alert History",
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
