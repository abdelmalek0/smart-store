cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# Suppress FindCUDA deprecation warning (we use it via OpenCV)
if(POLICY CMP0146)
  cmake_policy(SET CMP0146 OLD)
endif()

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Add OpenCV for texture manager (matching native_onnx plugin config)
set(OpenCV_DIR /opt/opencv-cuda/lib/cmake/opencv4)
find_package(OpenCV REQUIRED COMPONENTS core)
target_include_directories(${BINARY_NAME} PRIVATE ${OpenCV_INCLUDE_DIRS})
target_link_libraries(${BINARY_NAME} PRIVATE ${OpenCV_LIBS})

# Add OpenGL for texture manager
set(OpenGL_GL_PREFERENCE GLVND)
find_package(OpenGL REQUIRED)
target_link_libraries(${BINARY_NAME} PRIVATE OpenGL::GL OpenGL::GLX)
