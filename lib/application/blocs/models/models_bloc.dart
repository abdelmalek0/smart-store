import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:smart_store_linux/application/config/config_service.dart';
import 'package:smart_store_linux/domain/entities/config/model_config.dart';
import 'package:smart_store_linux/domain/use_cases/models/add_model.dart';
import 'package:smart_store_linux/domain/use_cases/models/remove_model.dart'
    as uc;
import 'package:smart_store_linux/domain/use_cases/models/update_model.dart';
import 'package:uuid/uuid.dart';
import 'models_event.dart';
import 'models_state.dart';

class ModelsBloc extends Bloc<ModelsEvent, ModelsState> {
  final AddModel _addModel;
  final uc.RemoveModel _removeModel;
  final UpdateModel _updateModel;
  final ConfigService _configService;

  ModelsBloc({
    required AddModel addModel,
    required uc.RemoveModel removeModel,
    required UpdateModel updateModel,
    required ConfigService configService,
  }) : _addModel = addModel,
       _removeModel = removeModel,
       _updateModel = updateModel,
       _configService = configService,
       super(const ModelsState()) {
    on<ModelsLoaded>(_onLoaded);
    on<ModelFileAdded>(_onModelFileAdded);
    on<ModelRemoved>(_onModelRemoved);
    on<ModelLabelsUpdated>(_onLabelsUpdated);

    _configService.addListener(_onConfigChanged);
  }

  void _onConfigChanged() {
    add(const ModelsLoaded());
  }

  void _onLoaded(ModelsLoaded event, Emitter<ModelsState> emit) {
    emit(
      state.copyWith(
        status: ModelsStatus.success,
        models: _configService.models,
      ),
    );
  }

  Future<void> _onModelFileAdded(
    ModelFileAdded event,
    Emitter<ModelsState> emit,
  ) async {
    final id = const Uuid().v4();
    final name = p.basename(event.path);
    final model = ModelConfig(id: id, path: event.path, name: name);
    await _addModel(model);
    emit(
      state.copyWith(
        status: ModelsStatus.success,
        models: _configService.models,
      ),
    );
  }

  Future<void> _onModelRemoved(
    ModelRemoved event,
    Emitter<ModelsState> emit,
  ) async {
    await _removeModel(event.modelId);
    emit(
      state.copyWith(
        status: ModelsStatus.success,
        models: _configService.models,
      ),
    );
  }

  Future<void> _onLabelsUpdated(
    ModelLabelsUpdated event,
    Emitter<ModelsState> emit,
  ) async {
    final model = _configService.getModel(event.modelId);
    if (model != null) {
      await _updateModel(model.copyWith(labels: event.labels));
      emit(
        state.copyWith(
          status: ModelsStatus.success,
          models: _configService.models,
        ),
      );
    }
  }

  /// Parse a label .txt file into classId → label map.
  Map<int, String>? parseLabelFile(String filePath) {
    try {
      final file = File(filePath);
      final lines = file.readAsLinesSync();
      final labels = <int, String>{};
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isNotEmpty) labels[i] = line;
      }
      return labels.isEmpty ? null : labels;
    } catch (e) {
      debugPrint('ModelsBloc: Error parsing label file: $e');
      return null;
    }
  }

  @override
  Future<void> close() {
    _configService.removeListener(_onConfigChanged);
    return super.close();
  }
}
