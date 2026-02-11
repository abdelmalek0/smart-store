#!/bin/bash

# Define replacement function
replace_import() {
    local old=$1
    local new=$2
    echo "Replacing $old with $new..."
    find lib test -name "*.dart" -type f -exec sed -i "s|$old|$new|g" {} +
}

# AI Layer
replace_import "package:smart_store_linux/ai/inference/backends/" "package:smart_store_linux/ai/backend/"
replace_import "package:smart_store_linux/ai/inference/service/inference_service.dart" "package:smart_store_linux/ai/service/inference_service.dart"
replace_import "package:smart_store_linux/ai/inference/worker/" "package:smart_store_linux/ai/worker/"
replace_import "package:smart_store_linux/ai/inference/messages.dart" "package:smart_store_linux/ai/worker/messages.dart"
replace_import "package:smart_store_linux/ai/inference/inference_result.dart" "package:smart_store_linux/ai/service/inference_result.dart"
replace_import "package:smart_store_linux/ai/post_processing/" "package:smart_store_linux/ai/utils/"

# Core Streaming
replace_import "package:smart_store_linux/backend/video/capture/" "package:smart_store_linux/core/streaming/capture/"
replace_import "package:smart_store_linux/backend/streaming/isolates/" "package:smart_store_linux/core/streaming/isolates/"
replace_import "package:smart_store_linux/backend/services/libvlc_bridge.dart" "package:smart_store_linux/core/streaming/drivers/libvlc_bridge.dart"
replace_import "package:smart_store_linux/core/models/rtsp_stream.dart" "package:smart_store_linux/core/streaming/models/rtsp_stream.dart"

# Core Rendering
replace_import "package:smart_store_linux/backend/video/renderer/" "package:smart_store_linux/core/rendering/"
replace_import "package:smart_store_linux/backend/services/texture_service.dart" "package:smart_store_linux/core/rendering/texture_service.dart"

# Core Engine
replace_import "package:smart_store_linux/backend/streaming/pipeline/" "package:smart_store_linux/core/engine/pipeline/"

# Core Plugins
replace_import "package:smart_store_linux/plugins/" "package:smart_store_linux/core/plugins/"
replace_import "package:smart_store_linux/core/registry/plugin_registry.dart" "package:smart_store_linux/core/plugins/registry/plugin_registry.dart"

# Core Config & Resources
replace_import "package:smart_store_linux/backend/services/config_service.dart" "package:smart_store_linux/core/config/config_service.dart"
replace_import "package:smart_store_linux/backend/services/resource_monitor/" "package:smart_store_linux/core/resources/"

# Core Events
replace_import "package:smart_store_linux/core/event/" "package:smart_store_linux/core/events/"

# Data Layer
replace_import "package:smart_store_linux/backend/services/persistence_service.dart" "package:smart_store_linux/data/services/persistence_service.dart"

# UI Layer
replace_import "package:smart_store_linux/ui/viewmodels/" "package:smart_store_linux/ui/viewModels/"
replace_import "package:smart_store_linux/ui/theme/" "package:smart_store_linux/ui/utils/theme/"

echo "Import replacements complete."
