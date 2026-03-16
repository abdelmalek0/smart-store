cmake_minimum_required(VERSION 3.10)
project(native_rknn)

set(CMAKE_CXX_STANDARD 14)

# RKNN runtime only exists for arm64-v8a (Rockchip NPU hardware).
# On other ABIs (e.g. x86_64 emulator) we produce an empty stub so the build
# succeeds; the Dart TFLite backend is used for inference on those platforms.
if(CMAKE_ANDROID_ARCH_ABI STREQUAL "arm64-v8a")

    # Header paths
    include_directories(src/main/cpp)

    # Import librknnrt
    add_library(rknnrt SHARED IMPORTED)
    set_target_properties(rknnrt PROPERTIES IMPORTED_LOCATION
        ${CMAKE_CURRENT_SOURCE_DIR}/src/main/jniLibs/${ANDROID_ABI}/librknnrt.so)

    # Import librga
    add_library(rga SHARED IMPORTED)
    set_target_properties(rga PROPERTIES IMPORTED_LOCATION
        ${CMAKE_CURRENT_SOURCE_DIR}/src/main/jniLibs/${ANDROID_ABI}/librga.so)

    # Build native_rknn
    add_library(native_rknn SHARED
        src/main/cpp/yolo_image.cc
        src/main/cpp/post_process.cc
    )

    # Link libs and logging
    find_library(log-lib log)
    find_library(android-lib android)

    target_link_libraries(native_rknn
        rknnrt
        rga
        ${log-lib}
        ${android-lib}
    )

else()

    # Stub: empty shared library so the plugin registers without crashes.
    # Inference on non-arm64 goes through TfliteInferenceBackend instead.
    add_library(native_rknn SHARED src/main/cpp/stub_x86.cc)
    find_library(log-lib log)
    target_link_libraries(native_rknn ${log-lib})

endif()
