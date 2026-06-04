cmake_minimum_required(VERSION 3.22.1)
project("golf_native" LANGUAGES CXX)

add_library(golf_native SHARED
    src/main/cpp/golf_native.cpp
)

# -O3：開啟積極最佳化與迴圈向量化（arm64-v8a 自動啟用 NEON SIMD）
# -ffast-math：允許浮點重排，進一步提升 SIMD 效率
target_compile_options(golf_native PRIVATE
    -O3
    -ffast-math
)

find_library(log-lib     log)        # __android_log_print
find_library(jni-lib     jnigraphics) # AndroidBitmap_lockPixels

target_link_libraries(golf_native
    ${log-lib}
    ${jni-lib}
)
