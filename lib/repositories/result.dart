/// 統一的結果包裝
/// 
/// 用於表示異步操作的成功或失敗
abstract class Result<T> {
  const Result();

  /// 將 Result 映射到另一個類型
  Result<U> map<U>(U Function(T) transform) {
    if (this is Success<T>) {
      return Success((this as Success<T>).data.let(transform));
    } else if (this is Failure<T>) {
      return Failure((this as Failure<T>).error, (this as Failure<T>).stackTrace);
    }
    throw UnimplementedError();
  }

  /// 執行成功或失敗的回調
  void when({
    required void Function(T data) onSuccess,
    required void Function(Exception error, StackTrace? stackTrace) onFailure,
  }) {
    if (this is Success<T>) {
      onSuccess((this as Success<T>).data);
    } else if (this is Failure<T>) {
      onFailure(
        (this as Failure<T>).error,
        (this as Failure<T>).stackTrace,
      );
    }
  }

  /// 獲取成功的數據或 null
  T? getOrNull() {
    if (this is Success<T>) {
      return (this as Success<T>).data;
    }
    return null;
  }

  /// 獲取失敗的異常或 null
  Exception? getErrorOrNull() {
    if (this is Failure<T>) {
      return (this as Failure<T>).error;
    }
    return null;
  }

  /// 判斷是否成功
  bool get isSuccess => this is Success<T>;

  /// 判斷是否失敗
  bool get isFailure => this is Failure<T>;
}

/// 成功結果
class Success<T> extends Result<T> {
  final T data;

  const Success(this.data);

  @override
  String toString() => 'Success($data)';

  /// let 函數：Kotlin 風格的作用域函數
  U let<U>(U Function(T) transform) => transform(data);
}

/// 失敗結果
class Failure<T> extends Result<T> {
  final Exception error;
  final StackTrace? stackTrace;

  const Failure(
    this.error, [
    this.stackTrace,
  ]);

  @override
  String toString() => 'Failure($error)';
}

/// 輔助函數：作用域函數擴展
extension ResultExtension<T> on Result<T> {
  /// 鏈式操作
  Future<Result<U>> flatMapAsync<U>(
    Future<Result<U>> Function(T) transform,
  ) async {
    if (this is Success<T>) {
      try {
        return await transform((this as Success<T>).data);
      } catch (e, st) {
        return Failure(Exception(e.toString()), st);
      }
    } else if (this is Failure<T>) {
      return Failure(
        (this as Failure<T>).error,
        (this as Failure<T>).stackTrace,
      );
    }
    throw UnimplementedError();
  }

  /// 獲取或拋出異常
  T getOrThrow() {
    if (this is Success<T>) {
      return (this as Success<T>).data;
    } else if (this is Failure<T>) {
      throw (this as Failure<T>).error;
    }
    throw UnimplementedError();
  }

  /// 取得或使用預設值
  T getOrElse(T Function(Exception) onError) {
    if (this is Success<T>) {
      return (this as Success<T>).data;
    } else if (this is Failure<T>) {
      return onError((this as Failure<T>).error);
    }
    throw UnimplementedError();
  }
}
