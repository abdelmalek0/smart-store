/*
 * Copyright (C) 2022 Rockchip Electronics Co., Ltd.
 * Authors:
 *  raul.rao <raul.rao@rock-chips.com>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <sys/time.h>
#include <vector>
#include <set>
#include "post_process.h"

inline static int clamp(float val, int min, int max)
{
    return val > min ? (val < max ? val : max) : min;
}

static float CalculateOverlap(float xmin0, float ymin0, float xmax0, float ymax0, float xmin1, float ymin1, float xmax1, float ymax1)
{
    float w = fmax(0.f, fmin(xmax0, xmax1) - fmax(xmin0, xmin1) + 1.0);
    float h = fmax(0.f, fmin(ymax0, ymax1) - fmax(ymin0, ymin1) + 1.0);
    float i = w * h;
    float u = (xmax0 - xmin0 + 1.0) * (ymax0 - ymin0 + 1.0) + (xmax1 - xmin1 + 1.0) * (ymax1 - ymin1 + 1.0) - i;
    return u <= 0.f ? 0.f : (i / u);
}

static int nms(int validCount, std::vector<float> &outputLocations, std::vector<int> classIds, std::vector<int> &order,int filterId, float threshold)
{
    for (int i = 0; i < validCount; ++i)
    {
        if (order[i] == -1|| classIds[i] != filterId)
        {
            continue;
        }
        int n = order[i];
        for (int j = i + 1; j < validCount; ++j)
        {
            int m = order[j];
            if (m == -1 || classIds[i] != filterId)
            {
                continue;
            }
            float xmin0 = outputLocations[n * 4 + 0];
            float ymin0 = outputLocations[n * 4 + 1];
            float xmax0 = outputLocations[n * 4 + 0] + outputLocations[n * 4 + 2];
            float ymax0 = outputLocations[n * 4 + 1] + outputLocations[n * 4 + 3];

            float xmin1 = outputLocations[m * 4 + 0];
            float ymin1 = outputLocations[m * 4 + 1];
            float xmax1 = outputLocations[m * 4 + 0] + outputLocations[m * 4 + 2];
            float ymax1 = outputLocations[m * 4 + 1] + outputLocations[m * 4 + 3];

            float iou = CalculateOverlap(xmin0, ymin0, xmax0, ymax0, xmin1, ymin1, xmax1, ymax1);

            if (iou > threshold)
            {
                order[j] = -1;
            }
        }
    }
    return 0;
}

static int quick_sort_indice_inverse(
        std::vector<float> &input,
        int left,
        int right,
        std::vector<int> &indices)
{
    float key;
    int key_index;
    int low = left;
    int high = right;
    if (left < right)
    {
        key_index = indices[left];
        key = input[left];
        while (low < high)
        {
            while (low < high && input[high] <= key)
            {
                high--;
            }
            input[low] = input[high];
            indices[low] = indices[high];
            while (low < high && input[low] >= key)
            {
                low++;
            }
            input[high] = input[low];
            indices[high] = indices[low];
        }
        input[low] = key;
        indices[low] = key_index;
        quick_sort_indice_inverse(input, left, low - 1, indices);
        quick_sort_indice_inverse(input, low + 1, right, indices);
    }
    return low;
}

static float sigmoid(float x)
{
    return 1.0 / (1.0 + expf(-x));
}

static float unsigmoid(float y)
{
    return -1.0 * logf((1.0 / y) - 1.0);
}

inline static int32_t __clip(float val, float min, float max)
{
    float f = val <= min ? min : (val >= max ? max : val);
    return f;
}

static int8_t qnt_f32_to_affine(float f32, int32_t zp, float scale)
{
    float dst_val = (f32 / scale) + zp;
    int8_t res = (int8_t)__clip(dst_val, -128, 127);
    return res;
}

static float deqnt_affine_to_f32(int8_t qnt, int32_t zp, float scale)
{
    return ((float)qnt - (float)zp) * scale;
}

static int process(float *input, int *anchor, int grid_h, int grid_w, int height, int width, int stride,
                   std::vector<float> &boxes, std::vector<float> &objProbs, std::vector<int> &classId,
                   float threshold, int32_t zp, float scale, int num_classes)
{

    int validCount = 0;
    int grid_len = grid_h * grid_w;
    float thres = unsigmoid(threshold);
    int prop_box_size = 5 + num_classes;
    // printf("THRESHOLD %f", thres);
    //int8_t thres_i8 = qnt_f32_to_affine(thres, zp, scale);
    for (int a = 0; a < 3; a++)
    {
        for (int i = 0; i < grid_h; i++)
        {
            for (int j = 0; j < grid_w; j++)
            {
                float box_confidence = input[(prop_box_size * a + 4) * grid_len + i * grid_w + j];
                if (box_confidence >= thres)
                {
                    int offset = (prop_box_size * a) * grid_len + i * grid_w + j;
                    float *in_ptr = input + offset;
#if 0
                    float box_x = sigmoid(deqnt_affine_to_f32(*in_ptr, zp, scale)) * 2.0 - 0.5;
                    float box_y = sigmoid(deqnt_affine_to_f32(in_ptr[grid_len], zp, scale)) * 2.0 - 0.5;
                    float box_w = sigmoid(deqnt_affine_to_f32(in_ptr[2 * grid_len], zp, scale)) * 2.0;
                    float box_h = sigmoid(deqnt_affine_to_f32(in_ptr[3 * grid_len], zp, scale)) * 2.0;
#endif
                    float box_x = sigmoid(*in_ptr) * 2.0 - 0.5;
                    float box_y = sigmoid(in_ptr[grid_len]) * 2.0 - 0.5;
                    float box_w = sigmoid(in_ptr[2 * grid_len]) * 2.0;
                    float box_h = sigmoid(in_ptr[3 * grid_len]) * 2.0;
                    box_x = (box_x + j) * (float)stride;
                    box_y = (box_y + i) * (float)stride;
                    box_w = box_w * box_w * (float)anchor[a * 2];
                    box_h = box_h * box_h * (float)anchor[a * 2 + 1];
                    box_x -= (box_w / 2.0);
                    box_y -= (box_h / 2.0);

                    float maxClassProbs = in_ptr[5 * grid_len];
                    int maxClassId = 0;
                    for (int k = 1; k < num_classes; ++k)
                    {
                        float prob = in_ptr[(5 + k) * grid_len];
                        if (prob > maxClassProbs)
                        {
                            maxClassId = k;
                            maxClassProbs = prob;
                        }
                    }
//                    float max_class_prob = deqnt_affine_to_f32(maxClassProbs, zp, scale);
//                    float box_prob = deqnt_affine_to_f32(box_confidence, zp, scale);
                    float max_class_prob = maxClassProbs;
                    float box_prob = box_confidence;
                    if (max_class_prob * box_prob > threshold){
                        boxes.push_back(box_x);
                        boxes.push_back(box_y);
                        boxes.push_back(box_w);
                        boxes.push_back(box_h);
                        objProbs.push_back(sigmoid(max_class_prob * box_prob));
                        classId.push_back(maxClassId);
                        validCount++;
                    }
                }
            }
        }
    }
    return validCount;
}

int post_process(float *input0, float *input1, float *input2, int model_in_h, int model_in_w,
                 float conf_threshold, float nms_threshold, float scale_w, float scale_h,
                 int pad_w, int pad_h, int num_classes,
                 std::vector<int32_t> &qnt_zps, std::vector<float> &qnt_scales,
                 detect_result_group_t *group)
{
//    LOGI("post process start.");
//    LOGI("qunt_zps: [%d, %d, %d]", qnt_zps[0], qnt_zps[1], qnt_zps[2]);
//    LOGI("qnt_scales: [%f, %f, %f]", qnt_scales[0], qnt_scales[1], qnt_scales[2]);

    // YOLOv5 anchors - using base 640x640 values WITHOUT scaling
    // Your model uses these anchors regardless of input size (320 or 640)
    int anchor0[6] = {10, 13, 16, 30, 33, 23};
    int anchor1[6] = {30, 61, 62, 45, 59, 119};
    int anchor2[6] = {116, 90, 156, 198, 373, 326};
    
    LOGI("ANCHORS: Using unscaled 640 anchors for %dx%d model", model_in_w, model_in_h);

    memset(group, 0, sizeof(detect_result_group_t));

    std::vector<float> filterBoxes;
    std::vector<float> objProbs;
    std::vector<int> classId;

    // stride 8
    int stride0 = 8;
    int grid_h0 = model_in_h / stride0;
    int grid_w0 = model_in_w / stride0;
    int validCount0 = 0;
    validCount0 = process(input0, (int *)anchor0, grid_h0, grid_w0, model_in_h, model_in_w,
                          stride0, filterBoxes, objProbs, classId, conf_threshold, 0, 1, num_classes);

    // stride 16
    int stride1 = 16;
    int grid_h1 = model_in_h / stride1;
    int grid_w1 = model_in_w / stride1;
    int validCount1 = 0;
    validCount1 = process(input1, (int *)anchor1, grid_h1, grid_w1, model_in_h, model_in_w,
                          stride1, filterBoxes, objProbs, classId, conf_threshold, 0, 1, num_classes);

    // stride 32
    int stride2 = 32;
    int grid_h2 = model_in_h / stride2;
    int grid_w2 = model_in_w / stride2;
    int validCount2 = 0;
    validCount2 = process(input2, (int *)anchor2, grid_h2, grid_w2, model_in_h, model_in_w,
                          stride2, filterBoxes, objProbs, classId, conf_threshold, 0, 1, num_classes);

    int validCount = validCount0 + validCount1 + validCount2;
//    LOGI("vc0: %d, vc1: %d, vc2: %d\n", validCount0, validCount1, validCount2);
    // no object detect
    if (validCount <= 0)
    {
//        LOGI("post process end.");
        return 0;
    }

    std::vector<int> indexArray;
    for (int i = 0; i < validCount; ++i)
    {
        indexArray.push_back(i);
    }

    quick_sort_indice_inverse(objProbs, 0, validCount - 1, indexArray);

    std::set<int> class_set(std::begin(classId),std::end(classId));

    for(auto c : class_set){
        nms(validCount, filterBoxes, classId, indexArray, c, nms_threshold);
    }

    int last_count = 0;
    group->count = 0;
    /* box valid detect target */
    for (int i = 0; i < validCount; ++i)
    {

        if (indexArray[i] == -1 || last_count >= OBJ_NUMB_MAX_SIZE)
        {
            continue;
        }
        int n = indexArray[i];

        float x1 = filterBoxes[n * 4 + 0];
        float y1 = filterBoxes[n * 4 + 1];
        float x2 = x1 + filterBoxes[n * 4 + 2];
        float y2 = y1 + filterBoxes[n * 4 + 3];
        int id = classId[n];
        float obj_conf = objProbs[i];




        
        // Calculate original image dimensions from model params
        int img_width = (int)((model_in_w - 2 * pad_w) / scale_w);
        int img_height = (int)((model_in_h - 2 * pad_h) / scale_h);
        
        // STRETCH MODE: Model was trained with direct resize (no aspect ratio preservation)
        float stretch_scale_w = (float)model_in_w / img_width;
        float stretch_scale_h = (float)model_in_h / img_height;
        
        int left = (int)(x1 / stretch_scale_w);
        int top = (int)(y1 / stretch_scale_h);
        int right = (int)(x2 / stretch_scale_w);
        int bottom = (int)(y2 / stretch_scale_h);
        
        if (last_count == 0) {
            // Show confirmation we're using stretch mode
            LOGI("====== USING STRETCH MODE ======\n");
            LOGI("Model coords: (%.1f,%.1f) -> (%.1f,%.1f)\n", x1, y1, x2, y2);
            LOGI("Output: (%d,%d,%d,%d)\n", left, top, right, bottom);
        }
        
        group->results[last_count].box.left = left;
        group->results[last_count].box.top = top;
        group->results[last_count].box.right = right;
        group->results[last_count].box.bottom = bottom;
        group->results[last_count].prop = obj_conf;
        group->results[last_count].class_id = id;
//        char *label = labels[id];
//        strncpy(group->results[last_count].name, label, OBJ_NAME_MAX_SIZE);

//        LOGI("result %2d: (%4d, %4d, %4d, %4d), %d\n", i, group->results[last_count].box.left, group->results[last_count].box.top,
//                group->results[last_count].box.right, group->results[last_count].box.bottom, id);
        last_count++;
    }
    group->count = last_count;
//    LOGI("post process end.");

    return 0;
}

void deinitPostProcess() {
    return;
}