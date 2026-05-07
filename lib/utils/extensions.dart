/// 字符串擴展
extension StringExtension on String {
  /// 檢查是否為空或僅包含空白
  bool get isEmptyOrWhitespace => trim().isEmpty;

  /// 檢查是否為有效的電郵
  bool get isValidEmail {
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    return emailRegex.hasMatch(this);
  }

  /// 首字母大寫
  String get capitalize => isEmpty ? '' : '${this[0].toUpperCase()}${substring(1)}';

  /// 移除所有空白
  String removeWhitespace() => replaceAll(RegExp(r'\s+'), '');

  /// 截斷字符串（如果超過指定長度）
  String truncate(int length, {String ellipsis = '...'}) {
    if (this.length <= length) return this;
    return '${substring(0, length - ellipsis.length)}$ellipsis';
  }

  /// 轉換為 bool
  bool? toBoolean() {
    final lowerCase = toLowerCase().trim();
    if (lowerCase == 'true' || lowerCase == '1' || lowerCase == 'yes') {
      return true;
    }
    if (lowerCase == 'false' || lowerCase == '0' || lowerCase == 'no') {
      return false;
    }
    return null;
  }
}

/// List 擴展
extension ListExtension<T> on List<T> {
  /// 安全地獲取元素（防止索引越界）
  T? getAt(int index) => index >= 0 && index < length ? this[index] : null;

  /// 分組列表
  List<List<T>> chunked(int chunkSize) {
    final chunks = <List<T>>[];
    for (int i = 0; i < length; i += chunkSize) {
      chunks.add(sublist(i, i + chunkSize > length ? length : i + chunkSize));
    }
    return chunks;
  }

  /// 檢查是否有重複元素
  bool hasDuplicates() {
    return length != toSet().length;
  }

  /// 返回不包括最後一個元素的列表
  List<T> dropLast() => isEmpty ? [] : sublist(0, length - 1);

  /// 返回最後一個元素（安全）
  T? getLastOrNull() => isEmpty ? null : last;

  /// 返回第一個元素（安全）
  T? getFirstOrNull() => isEmpty ? null : first;
}

/// Map 擴展
extension MapExtension<K, V> on Map<K, V> {
  /// 安全地獲取值
  V? getSafe(K key) => containsKey(key) ? this[key] : null;

  /// 從 Map 中提取特定鍵
  Map<K, V> extractKeys(Iterable<K> keys) {
    return {
      for (final key in keys)
        if (containsKey(key)) key: this[key] as V,
    };
  }

  /// 反轉 Map（鍵值對調）
  Map<V, K> reverse() {
    return {
      for (final entry in entries) entry.value: entry.key,
    };
  }

  /// 將 Map 轉換為 Query String
  String toQueryString() {
    return entries
        .map((e) => '${Uri.encodeComponent(e.key.toString())}=${Uri.encodeComponent(e.value.toString())}')
        .join('&');
  }

  /// 合併另一個 Map
  Map<K, V> merge(Map<K, V> other) {
    return {...this, ...other};
  }
}

/// DateTime 擴展
extension DateTimeExtension on DateTime {
  /// 檢查是否為今天
  bool get isToday {
    final now = DateTime.now();
    return year == now.year && month == now.month && day == now.day;
  }

  /// 檢查是否為昨天
  bool get isYesterday {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return year == yesterday.year && month == yesterday.month && day == yesterday.day;
  }

  /// 檢查是否為特定日期
  bool isSameDateAs(DateTime other) {
    return year == other.year && month == other.month && day == other.day;
  }

  /// 距離現在的時間差描述
  String get timeAgoDescription {
    final now = DateTime.now();
    final difference = now.difference(this);

    if (difference.inSeconds < 60) {
      return '${difference.inSeconds}秒前';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}分鐘前';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}小時前';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}天前';
    } else {
      return toString().split(' ')[0]; // 返回日期部分
    }
  }

  /// 格式化為 HH:mm
  String toTimeString() => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  /// 格式化為 yyyy-MM-dd
  String toDateString() => '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  /// 取得本週開始（週一）
  DateTime get weekStart {
    final now = toLocal();
    return now.subtract(Duration(days: now.weekday - 1));
  }

  /// 取得本月開始
  DateTime get monthStart => DateTime(year, month);

  /// 取得本月結束
  DateTime get monthEnd => DateTime(year, month + 1, 0);
}

/// Duration 擴展
extension DurationExtension on Duration {
  /// 格式化為 HH:mm:ss
  String get formatted {
    final hours = inHours;
    final minutes = inMinutes.remainder(60);
    final seconds = inSeconds.remainder(60);
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// 格式化為 mm:ss
  String get shortFormat {
    final minutes = inMinutes;
    final seconds = inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// 取得描述性文本
  String get description {
    if (inDays > 0) {
      return '${inDays}天';
    } else if (inHours > 0) {
      return '${inHours}小時';
    } else if (inMinutes > 0) {
      return '${inMinutes}分鐘';
    } else {
      return '${inSeconds}秒';
    }
  }
}

/// num 擴展（int 和 double）
extension NumExtension on num {
  /// 檢查是否在範圍內
  bool isBetween(num min, num max) => this >= min && this <= max;

  /// 限制在範圍內
  num clamp(num min, num max) {
    if (this < min) return min;
    if (this > max) return max;
    return this;
  }

  /// 格式化為百分比字符串
  String toPercentString({int decimals = 1}) {
    return '${(this * 100).toStringAsFixed(decimals)}%';
  }

  /// 格式化為固定小數位數
  String toFixedString(int decimals) => toStringAsFixed(decimals);

  /// 將字節轉換為可讀格式
  String get bytesReadableSize {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = toDouble();
    var unitIndex = 0;

    while (size > 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }

    return '${size.toStringAsFixed(2)} ${units[unitIndex]}';
  }
}

/// Iterable 擴展
extension IterableExtension<T> on Iterable<T> {
  /// 安全的索引訪問
  T? elementAtOrNull(int index) {
    if (index < 0) return null;
    for (final element in this) {
      if (index == 0) return element;
      index--;
    }
    return null;
  }

  /// 按條件分組
  Map<K, List<T>> groupBy<K>(K Function(T) keySelector) {
    final groups = <K, List<T>>{};
    for (final element in this) {
      final key = keySelector(element);
      groups.putIfAbsent(key, () => []).add(element);
    }
    return groups;
  }

  /// 去重
  List<T> distinct() => toSet().toList();

  /// 查找最大值（根據選擇器）
  T? maxBy<R extends Comparable<R>>(R Function(T) selector) {
    if (isEmpty) return null;
    return reduce((a, b) => selector(a).compareTo(selector(b)) > 0 ? a : b);
  }

  /// 查找最小值（根據選擇器）
  T? minBy<R extends Comparable<R>>(R Function(T) selector) {
    if (isEmpty) return null;
    return reduce((a, b) => selector(a).compareTo(selector(b)) < 0 ? a : b);
  }
}
