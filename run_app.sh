#!/bin/bash
# Flutter app launcher with OpenCV CUDA library path

export LD_LIBRARY_PATH=/opt/opencv-cuda/lib:$LD_LIBRARY_PATH

flutter run -d linux "$@"
