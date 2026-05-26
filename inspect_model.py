import struct, sys

data = open("assets/models/golfballyolov8n_int8.tflite", "rb").read()
print(f"Size: {len(data)}")

# Try to find tensor shape info by searching for known patterns
# TFLite FlatBuffer: root table at offset stored in first 4 bytes
root_off = struct.unpack_from("<I", data, 0)[0]
print(f"Root offset: {root_off}")
print(f"Identifier: {data[4:8]}")

# Search for all sequences: n*4 bytes of int32s that look like tensor shapes
# Common YOLOv8 shapes to find: [1, H, W, 3] and [1, n, 8400]
shapes_found = {}
for i in range(0, len(data)-20, 4):
    try:
        vals = struct.unpack_from("<5i", data, i)
        # Look for [1, H, H, 3] input shape
        if vals[0] == 1 and vals[1] == vals[2] and vals[1] in (320,416,448,480,512,640) and vals[3] == 3:
            shapes_found[f"NHWC_input_at_{i}"] = list(vals[:4])
        # Look for [1, n, 8400] output
        if vals[0] == 1 and vals[2] == 8400 and 4 <= vals[1] <= 85:
            shapes_found[f"output_at_{i}"] = list(vals[:3])
        # [1, 8400, n]
        if vals[0] == 1 and vals[1] == 8400 and 4 <= vals[2] <= 85:
            shapes_found[f"output_T_at_{i}"] = list(vals[:3])
    except:
        pass

for k, v in shapes_found.items():
    print(f"  {k}: {v}")
