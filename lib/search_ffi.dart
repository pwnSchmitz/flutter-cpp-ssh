import 'dart:ffi';
import 'dart:io';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

// Тип callback из C++
typedef SearchResultCallbackNative = ffi.Void Function(
  ffi.Int32 requestId,
  ffi.Uint8 found,
  ffi.Pointer<ffi.Char> filename,
  ffi.Pointer<ffi.Char> linePreview,
  ffi.Int32 lineNumber,
  ffi.Double searchTimeMs,
);

typedef SearchResultCallbackDart = void Function(
  int requestId,
  bool found,
  String filename,
  String linePreview,
  int lineNumber,
  double searchTimeMs,
);

// Нативные функции
typedef SearchInitNative = ffi.Void Function();
typedef SearchStartNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Pointer<ffi.Char>> filepaths,
  ffi.Int32 fileCount,
  ffi.Pointer<ffi.Char> targetNumber,
  ffi.Pointer<ffi.NativeFunction<SearchResultCallbackNative>> callback,
);
typedef SearchCancelNative = ffi.Void Function(ffi.Int32 requestId);
typedef SearchCleanupNative = ffi.Void Function();

class SearchEngineFFI {
  late final DynamicLibrary _lib;
  late final SearchResultCallbackDart _dartCallback;
  
  SearchEngineFFI._();
  
  static Future<SearchEngineFFI> create({required SearchResultCallbackDart callback}) async {
    final instance = SearchEngineFFI._();
    instance._dartCallback = callback;
    
    // Загрузка DLL
    if (Platform.isWindows) {
      instance._lib = DynamicLibrary.open('search_engine.dll');
    } else if (Platform.isLinux) {
      instance._lib = DynamicLibrary.open('libsearch_engine.so');
    } else if (Platform.isMacOS) {
      instance._lib = DynamicLibrary.open('libsearch_engine.dylib');
    } else {
      throw UnsupportedError('Platform not supported');
    }
    
    return instance;
  }
  
  void init() => _init();
  void _init() => _searchInit();
  
  late final _searchInit = _lib
      .lookup<ffi.NativeFunction<SearchInitNative>>('search_init')
      .asFunction<void Function()>();
  
  int start(List<String> filepaths, String targetNumber) {
    // Выделяем память для массива строк
    final filePathsPtr = calloc<ffi.Pointer<ffi.Char>>(filepaths.length);
    for (int i = 0; i < filepaths.length; i++) {
      filePathsPtr[i] = filepaths[i].toNativeUtf8().cast<ffi.Char>();
    }
    
    final targetPtr = targetNumber.toNativeUtf8().cast<ffi.Char>();
    final callbackPtr = Pointer.fromFunction<SearchResultCallbackNative>(_nativeCallback);
    
    final requestId = _searchStart(filePathsPtr, filepaths.length, targetPtr, callbackPtr);
    
    // Освобождаем память
    for (int i = 0; i < filepaths.length; i++) {
      calloc.free(filePathsPtr[i]);
    }
    calloc.free(filePathsPtr);
    calloc.free(targetPtr);
    
    return requestId;
  }
  
  late final _searchStart = _lib
      .lookup<ffi.NativeFunction<SearchStartNative>>('search_start')
      .asFunction<int Function(
        ffi.Pointer<ffi.Pointer<ffi.Char>>,
        int,
        ffi.Pointer<ffi.Char>,
        ffi.Pointer<ffi.NativeFunction<SearchResultCallbackNative>>,
      )>();
  
  void cancel(int requestId) => _searchCancel(requestId);
  
  late final _searchCancel = _lib
      .lookup<ffi.NativeFunction<SearchCancelNative>>('search_cancel')
      .asFunction<void Function(int)>();
  
  void cleanup() => _searchCleanup();
  
  late final _searchCleanup = _lib
      .lookup<ffi.NativeFunction<SearchCleanupNative>>('search_cleanup')
      .asFunction<void Function()>();
  
  // Нативный коллбек -> Dart
  void _nativeCallback(
    int requestId,
    int found,
    ffi.Pointer<ffi.Char> filename,
    ffi.Pointer<ffi.Char> linePreview,
    int lineNumber,
    double searchTimeMs,
  ) {
    final filenameStr = filename.cast<Utf8>().toDartString();
    final previewStr = linePreview.cast<Utf8>().toDartString();
    
    // Вызываем Dart callback в главном потоке
    _dartCallback(
      requestId,
      found != 0,
      filenameStr,
      previewStr,
      lineNumber,
      searchTimeMs,
    );
  }
}