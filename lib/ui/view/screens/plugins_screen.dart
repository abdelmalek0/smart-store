import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_store_linux/core/services/app/app_service.dart';
import 'package:smart_store_linux/ui/viewModels/plugins_viewmodel.dart';
import 'package:smart_store_linux/ui/view/widgets/modern/modern_widgets.dart';
import 'package:smart_store_linux/ui/view/widgets/cards/plugin_card.dart';

class PluginsScreen extends StatefulWidget {
  final Function(String, String) onModelChanged;

  const PluginsScreen({super.key, required this.onModelChanged});

  @override
  State<PluginsScreen> createState() => _PluginsScreenState();
}

class _PluginsScreenState extends State<PluginsScreen> {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PluginsViewModel(AppService.instance),
      child: _PluginsContent(onModelChanged: widget.onModelChanged),
    );
  }
}

class _PluginsContent extends StatelessWidget {
  final Function(String, String) onModelChanged;

  const _PluginsContent({required this.onModelChanged});

  @override
  Widget build(BuildContext context) {
    return Consumer<PluginsViewModel>(
      builder: (context, vm, _) {
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
                itemCount: vm.plugins.length,
                itemBuilder: (context, index) {
                  final plugin = vm.plugins[index];
                  return PluginCard(
                    plugin: plugin,
                    vm: vm,
                    onModelChanged: onModelChanged,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
