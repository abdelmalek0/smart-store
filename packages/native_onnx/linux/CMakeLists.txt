
cmake_minimum_required(VERSION 3.10)



set(PROJECT_NAME "native_onnx")
project(${PROJECT_NAME} LANGUAGES CXX)

# Suppress FindCUDA deprecation warning (we use it via OpenCV)
if(POLICY CMP0146)
  cmake_policy(SET CMP0146 OLD)
  set(CMAKE_POLICY_DEFAULT_CMP0146 OLD)
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(PLUGIN_NAME "native_onnx_plugin")

# Add my bridge source
list(APPEND PLUGIN_SOURCES
  "native_onnx_plugin.cc"
  "inference_bridge.cpp"
  "texture_manager.cpp"
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

# Add OpenGL for texture rendering
set(OpenGL_GL_PREFERENCE GLVND)  # Use modern GLVND instead of legacy
find_package(OpenGL REQUIRED)
target_link_libraries(${PLUGIN_NAME} PRIVATE OpenGL::GL)
target_link_libraries(${PLUGIN_NAME} PRIVATE OpenGL::GLX)

# Use custom OpenCV with CUDA support
set(OpenCV_DIR /opt/opencv-cuda/lib/cmake/opencv4)
find_package(OpenCV REQUIRED COMPONENTS
  core imgproc videoio dnn cudaimgproc cudawarping
)

target_include_directories(${PLUGIN_NAME} PRIVATE ${OpenCV_INCLUDE_DIRS})
target_link_libraries(${PLUGIN_NAME} PRIVATE ${OpenCV_LIBS})

# Add CUDA support flags
target_compile_definitions(${PLUGIN_NAME} PRIVATE USE_CUDA)
target_compile_definitions(${PLUGIN_NAME} PRIVATE HAVE_OPENCV_CUDAIMGPROC)

# Add CUDA include directories and libraries
find_package(CUDA QUIET)
if(CUDA_FOUND)
  target_include_directories(${PLUGIN_NAME} PRIVATE ${CUDA_INCLUDE_DIRS})
  
  # Link against CUDA runtime library
  # First try to use bundled libcudart, fallback to system CUDA
  if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/libs/libcudart.so.12")
    target_link_libraries(${PLUGIN_NAME} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/libs/libcudart.so.12")
    message(STATUS "Using bundled CUDA runtime library")
  elseif(CUDA_LIBRARIES)
    target_link_libraries(${PLUGIN_NAME} PRIVATE ${CUDA_LIBRARIES})
    message(STATUS "Using system CUDA runtime library: ${CUDA_LIBRARIES}")
  endif()
  
  # Link NPP libraries for GPU-native NV12 to RGBA conversion
  find_library(NPP_CORE_LIB nppc HINTS ${CUDA_TOOLKIT_ROOT_DIR}/lib64)
  find_library(NPP_IMGPROC_LIB nppig HINTS ${CUDA_TOOLKIT_ROOT_DIR}/lib64)
  find_library(NPP_COLOR_LIB nppicc HINTS ${CUDA_TOOLKIT_ROOT_DIR}/lib64)
  
  if(NPP_CORE_LIB AND NPP_IMGPROC_LIB AND NPP_COLOR_LIB)
    target_link_libraries(${PLUGIN_NAME} PRIVATE ${NPP_CORE_LIB} ${NPP_IMGPROC_LIB} ${NPP_COLOR_LIB})
    target_compile_definitions(${PLUGIN_NAME} PRIVATE USE_NPP)
    message(STATUS "NPP libraries found - enabling GPU-native NV12 conversion")
  else()
    message(WARNING "NPP libraries not found - falling back to CPU NV12 conversion")
  endif()
endif()

# Add FFmpeg libraries for hardware video decoding (NVDEC)
find_package(PkgConfig REQUIRED)
pkg_check_modules(FFMPEG REQUIRED
  libavcodec
  libavformat
  libavutil
  libswscale
)

target_include_directories(${PLUGIN_NAME} PRIVATE ${FFMPEG_INCLUDE_DIRS})
target_link_libraries(${PLUGIN_NAME} PRIVATE ${FFMPEG_LIBRARIES})

message(STATUS "FFmpeg libraries found:")
message(STATUS "  libavcodec: ${FFMPEG_libavcodec_VERSION}")
message(STATUS "  libavformat: ${FFMPEG_libavformat_VERSION}")
message(STATUS "  libavutil: ${FFMPEG_libavutil_VERSION}")
message(STATUS "  libswscale: ${FFMPEG_libswscale_VERSION}")

# Add compile definition to enable FFmpeg NVDEC code path
target_compile_definitions(${PLUGIN_NAME} PRIVATE USE_FFMPEG_NVDEC)


# Link against ONNX Runtime
target_link_libraries(${PLUGIN_NAME} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/libs/libonnxruntime.so")

# Set RPATH so the plugin can find onnxruntime and OpenCV libraries
set_target_properties(${PLUGIN_NAME} PROPERTIES
    INSTALL_RPATH "$ORIGIN:/opt/opencv-cuda/lib"
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