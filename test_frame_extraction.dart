#!/usr/bin/env dart
// ignore_for_file: avoid_print  (獨立 CLI 測試工具，print 即輸出)

import 'package:flutter/services.dart';

void main() async {
  print('🧪 Frame Extraction Test Script');
  print('================================\n');
  
  const frameExtractorChannel = 
      MethodChannel('com.example.golf_score_app/frame_extractor');
  
  const videoPath = '/sdcard/Download/golf_1753430732426.mp4';
  
  // Check if video exists
  print('📹 Testing video: $videoPath');
  
  try {
    // Test 1: Extract frame at time 0
    print('\n🔄 Test 1: Extracting frame at 0ms...');
    final result = await frameExtractorChannel.invokeMethod(
      'extractFrameRgb',
      {
        'videoPath': videoPath,
        'timeMs': 0,
        'maxWidth': 720,
      },
    ) as Map<dynamic, dynamic>?;
    
    if (result != null) {
      final width = result['width'] as int;
      final height = result['height'] as int;
      final pixels = result['pixels'] as List<int>;
      print('✅ SUCCESS: Frame extracted: ${width}x$height, ${pixels.length} bytes');
      print('   First 10 pixels: ${pixels.take(10).toList()}');
    } else {
      print('❌ FAILED: Result is null');
    }
    
    // Test 2: Extract frame at time 1000ms
    print('\n🔄 Test 2: Extracting frame at 1000ms...');
    final result2 = await frameExtractorChannel.invokeMethod(
      'extractFrameRgb',
      {
        'videoPath': videoPath,
        'timeMs': 1000,
        'maxWidth': 720,
      },
    ) as Map<dynamic, dynamic>?;
    
    if (result2 != null) {
      final width = result2['width'] as int;
      final height = result2['height'] as int;
      final pixels = result2['pixels'] as List<int>;
      print('✅ SUCCESS: Frame extracted: ${width}x$height, ${pixels.length} bytes');
    } else {
      print('❌ FAILED: Result is null');
    }
    
  } on PlatformException catch (e) {
    print('❌ Platform Exception: ${e.code}');
    print('   Message: ${e.message}');
  } catch (e) {
    print('❌ Error: $e');
  }
}
