import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_store_linux/services/config_service.dart';
import 'package:smart_store_linux/core/di/injection_container.dart';
import 'package:smart_store_linux/presentation/blocs/events_log/events_log_bloc.dart';
import 'package:smart_store_linux/presentation/blocs/events_log/events_log_event.dart';
import 'package:smart_store_linux/presentation/blocs/events_log/events_log_state.dart';
import 'package:smart_store_linux/ui/view/widgets/cards/event_card.dart';

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
                            TextButton(
                              onPressed: () => _addMockEvent(context),
                              child: const Text("Add Test Event (Debug)"),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: state.events.length,
                        itemBuilder: (context, index) {
                          final event = state.events[index];
                          final streamConfig = ConfigService.instance.getStream(
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

  void _addMockEvent(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final types = ['CRITICAL', 'WARNING', 'INFO'];
    final type = types[now % 3];

    String msg = "Something happened";
    if (type == 'CRITICAL') {
      msg = "Queue limit exceeded\nCheckout 3 queue time > 5 mins.";
    } else if (type == 'WARNING') {
      msg = "Low Staff Presence\nElectronics zone staff ratio below 1:5.";
    } else if (type == 'INFO') {
      msg = "Restock Required\nEmpty shelf detected in Aisle 4.";
    }

    context.read<EventsLogBloc>().add(
      EventsLogMockAdded({
        'eventType': type,
        'streamId': 'Camera ${now % 4 + 1}',
        'timestamp': now,
        'data': {'msg': msg},
      }),
    );
  }
}
