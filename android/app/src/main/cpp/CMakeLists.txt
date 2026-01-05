cmake_minimum_required(VERSION 3.18.1)

project("ffmpeg_video")

# Add ffmpeg_video library  
add_library(ffmpeg_video SHARED vlc_video_bridge.cpp)

# Link with Android log library
find_library(log-lib log)
target_link_libraries(ffmpeg_video ${log-lib})
