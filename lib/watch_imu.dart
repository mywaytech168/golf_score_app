import 'dart:async';
import 'package:flutter/services.dart';

class WatchImu {
  static final WatchImu _instance = WatchImu._internal();
  factory WatchImu() => _instance;
  WatchImu._internal();

  static const EventChannel _eventChannel = EventChannel('watch_imu_stream');
  static const MethodChannel _methodChannel = MethodChannel('watch_imu_control');

  Stream<Map<String, dynamic>>? _imuStream;

  /// 監聽 Watch IMU 數據流
  Stream<Map<String, dynamic>> get imuStream {
    _imuStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((event) => Map<String, dynamic>.from(event as Map));
    return _imuStream!;
  }

  /// 啟動 Watch IMU 傳輸
  Future<bool> startIMU() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('startIMU');
      return result ?? false;
    } catch (e) {
      print('startIMU error: $e');
      return false;
    }
  }

  /// 停止 Watch IMU 傳輸
  Future<bool> stopIMU() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('stopIMU');
      return result ?? false;
    } catch (e) {
      print('stopIMU error: $e');
      return false;
    }
  }

  /// 檢查 Watch 是否可達（在範圍內且 App 開啟）
  Future<bool> isWatchReachable() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('isWatchReachable');
      return result ?? false;
    } catch (e) {
      print('isWatchReachable error: $e');
      return false;
    }
  }

  /// 檢查 Watch App 是否已安裝
  Future<bool> isWatchAppInstalled() async {
    try {
      final result = await _methodChannel.invokeMethod<bool>('isWatchAppInstalled');
      return result ?? false;
    } catch (e) {
      print('isWatchAppInstalled error: $e');
      return false;
    }
  }
}
