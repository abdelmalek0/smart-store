import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_store_linux/core/di/injection_container.dart';
import 'package:smart_store_linux/presentation/blocs/plugins/plugins_bloc.dart';
import 'package:smart_store_linux/presentation/blocs/plugins/plugins_event.dart';
import 'package:smart_store_linux/presentation/blocs/plugins/plugins_state.dart';
import 'package:smart_store_linux/ui/view/widgets/modern/modern_widgets.dart';
import 'package:smart_store_linux/ui/view/widgets/cards/plugin_card.dart';

class PluginsScreen extends StatelessWidget {
  const PluginsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<PluginsBloc>(
      create: (_) => sl<PluginsBloc>()..add(const PluginsLoaded()),
      child: BlocBuilder<PluginsBloc, PluginsState>(
        builder: (context, state) {
          return Column(
            children: [
              const ModernHeader(
                title: "Plugins",
                subtitle: "Manage system capabilities",
              ),
              const SizedBox(height: 20),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: state.plugins.length,
                  itemBuilder: (context, index) {
                    final plugin = state.plugins[index];
                    return PluginCard(plugin: plugin);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
