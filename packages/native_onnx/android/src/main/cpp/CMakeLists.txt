cmake_minimum_required(VERSION 3.18)
project(native_onnx_plugin)

set(CMAKE_CXX_STANDARD 17)

# Create shared library
add_library(native_onnx_plugin SHARED
    vlc_video_bridge.cpp
)

# Link with Android log library
find_library(log-lib log)
target_link_libraries(native_onnx_plugin ${log-lib})

# LibVLC will be linked via Gradle AAR dependency
