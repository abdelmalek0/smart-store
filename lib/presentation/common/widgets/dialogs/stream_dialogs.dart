import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_store_linux/application/blocs/streams/streams_bloc.dart';
import 'package:smart_store_linux/application/blocs/streams/streams_event.dart';

/// Shows the "Add Stream" dialog. Dispatches [StreamAdded] to the [StreamsBloc].
void showAddStreamDialog(BuildContext context) {
  final urlController = TextEditingController();
  final nameController = TextEditingController();
  final bloc = context.read<StreamsBloc>();

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: const Text(
        "Add New Camera",
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildDialogInput(nameController, "Camera Name (e.g. Entrance)"),
          const SizedBox(height: 16),
          _buildDialogInput(urlController, "RTSP URL (rtsp://...)"),
        ],
      ),
      actions: [
        TextButton(
          child: const Text(
            "Cancel",
            style: TextStyle(color: Color(0xFF94A3B8)),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
          ),
          child: const Text("Connect"),
          onPressed: () {
            if (urlController.text.isNotEmpty) {
              bloc.add(
                StreamAdded(
                  name: nameController.text.isNotEmpty
                      ? nameController.text
                      : urlController.text,
                  url: urlController.text,
                ),
              );
              Navigator.pop(context);
            }
          },
        ),
      ],
    ),
  );
}

Widget _buildDialogInput(TextEditingController controller, String hint) {
  return TextField(
    controller: controller,
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF64748B)),
      filled: true,
      fillColor: const Color(0xFF0F172A),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );
}
