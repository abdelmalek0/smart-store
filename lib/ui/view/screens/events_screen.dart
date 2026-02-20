import 'package:flutter/material.dart';
import 'package:smart_store_linux/core/config/config_service.dart';
import 'package:smart_store_linux/core/services/app/app_service.dart';
import 'package:smart_store_linux/ui/viewModels/events_viewmodel.dart';
import 'package:smart_store_linux/ui/view/widgets/cards/event_card.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  late final EventsViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = EventsViewModel(AppService.instance);
    _vm.addListener(_onViewModelChanged);
  }

  void _onViewModelChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _vm.removeListener(_onViewModelChanged);
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _EventsContent(vm: _vm);
  }
}

class _EventsContent extends StatelessWidget {
  final EventsViewModel vm;

  const _EventsContent({required this.vm});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF111722), // Updated dark background
      child: Column(
        children: [
          // Optional Header or just padding
          const SizedBox(height: 16),

          Expanded(
            child: vm.events.isEmpty
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
                          onPressed: () {
                            // Mock Event Generation for Testing
                            _addMockEvent();
                          },
                          child: const Text("Add Test Event (Debug)"),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: vm.events.length,
                    itemBuilder: (context, index) {
                      final event = vm.events[index];
                      // Resolve Camera Name from ConfigService
                      final streamId = event.streamId;
                      final streamConfig = ConfigService.instance.getStream(
                        streamId,
                      );
                      final streamName = streamConfig?.name ?? streamId;

                      return EventCard(event: event, streamName: streamName);
                    },
                  ),
          ),

          // clear button (temporary or persistence needed?)
          if (vm.events.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => vm.clearEvents(),
                    child: const Text(
                      "Clear All",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),

          // Footer
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: TextButton(
              onPressed: () {
                // View history logic
              },
              child: const Text(
                "View Alert History",
                style: TextStyle(
                  color: Color(0xFF94A3B8), // Slate-400
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _addMockEvent() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final types = ['CRITICAL', 'WARNING', 'INFO'];
    final type = types[now % 3];

    String msg = "Something happened";
    if (type == 'CRITICAL') {
      msg = "Queue limit exceeded\nCheckout 3 queue time > 5 mins.";
    }
    if (type == 'WARNING') {
      msg = "Low Staff Presence\nElectronics zone staff ratio below 1:5.";
    }
    if (type == 'INFO') {
      msg = "Restock Required\nEmpty shelf detected in Aisle 4.";
    }

    vm.addEvent({
      'eventType': type, // This will be parsed as severity by ViewModel
      'streamId': 'Camera ${now % 4 + 1}',
      'timestamp': now,
      'data': {'msg': msg},
    });
  }
}
