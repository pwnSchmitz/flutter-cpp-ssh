#pragma once

#ifdef _WIN32
    #define EXPORT __declspec(dllexport)
#else
    #define EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Callback тип для уведомления Flutter о результате
typedef void (*SearchResultCallback)(
    int request_id,
    bool found,
    const char* filename,
    const char* line_preview,
    int line_number,
    double search_time_ms
);

// Инициализация (вызывать один раз при старте)
EXPORT void search_init();

// Асинхронный поиск в нескольких файлах
// Возвращает request_id для отслеживания
EXPORT int search_start(
    const char** filepaths,     // массив путей к файлам
    int file_count,             // количество файлов
    const char* target_number,  // искомый номер
    SearchResultCallback callback // callback для результата
);

// Отмена поиска по request_id
EXPORT void search_cancel(int request_id);

// Освобождение памяти (если нужно)
EXPORT void search_cleanup();

#ifdef __cplusplus
}
#endif