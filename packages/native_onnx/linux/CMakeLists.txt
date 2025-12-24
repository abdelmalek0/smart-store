
cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "native_onnx")
project(${PROJECT_NAME} LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(PLUGIN_NAME "native_onnx_plugin")

# Add my bridge source
list(APPEND PLUGIN_SOURCES
  "native_onnx_plugin.cc"
  "inference_bridge.cpp"
)

add_library(${PLUGIN_NAME} SHARED
  ${PLUGIN_SOURCES}
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
  
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

# Include ONNX Headers
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_include_directories(${PLUGIN_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)

# Find OpenCV
pkg_check_modules(OPENCV REQUIRED opencv4)
target_include_directories(${PLUGIN_NAME} PRIVATE ${OPENCV_INCLUDE_DIRS})
target_link_libraries(${PLUGIN_NAME} PRIVATE ${OPENCV_LIBRARIES})

# Link against ONNX Runtime
target_link_libraries(${PLUGIN_NAME} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/libs/libonnxruntime.so")

# Set RPATH so the plugin can find onnxruntime in the same folder
set_target_properties(${PLUGIN_NAME} PROPERTIES
    INSTALL_RPATH "$ORIGIN"
    BUILD_WITH_INSTALL_RPATH TRUE
)

# Bundle the ONNX libraries
# This tells Flutter to copy these files to the final bundle/lib directory
file(GLOB ONNX_LIBS "${CMAKE_CURRENT_SOURCE_DIR}/libs/libonnxruntime.so*")
file(GLOB ONNX_PROVIDERS "${CMAKE_CURRENT_SOURCE_DIR}/libs/libonnxruntime_providers_*.so")
file(GLOB CUDA_DEPS "${CMAKE_CURRENT_SOURCE_DIR}/libs/libcudart.so*")
file(GLOB CUDNN_DEPS "${CMAKE_CURRENT_SOURCE_DIR}/libs/libcudnn*.so*")

set(native_onnx_bundled_libraries
  ${ONNX_LIBS}
  ${ONNX_PROVIDERS}
  ${CUDA_DEPS}
  ${CUDNN_DEPS}
  PARENT_SCOPE
)

# Optional: RPATH patching for the provider (CUDA provider needs it to find cudnn next to it)
# Plugins can't easy run install(CODE) into the main app safely generically, 
# but usually we rely on patchelf being done on the bundled libs if needed.
# Since we copy them, we might need a custom step or assume they are pre-patched or env works.
# For now, let's stick to simple bundling. The previous manual install() had patchelf steps.
# Flutter plugin system copies these files.