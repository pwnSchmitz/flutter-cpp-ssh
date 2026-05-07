#include "search_engine.h"
#include <iostream>
#include <string>
#include <algorithm>
#define NOMINMAX
#include <windows.h>

static SearchResultCallback g_callback = nullptr;

static std::string wstring_to_utf8(const std::wstring& wstr) {
    if (wstr.empty()) return "";
    int size_needed = WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), -1, nullptr, 0, nullptr, nullptr);
    std::string str(size_needed, 0);
    WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), -1, &str[0], size_needed, nullptr, nullptr);
    return str;
}

// Пробуем конвертировать из CP1251 в UTF-8
static std::string cp1251_to_utf8(const std::string& cp1251_str) {
    if (cp1251_str.empty()) return "";
    int size_w = MultiByteToWideChar(1251, 0, cp1251_str.c_str(), -1, nullptr, 0);
    if (size_w == 0) return cp1251_str; // Если не получилось, возвращаем как есть
    std::wstring wstr(size_w, 0);
    MultiByteToWideChar(1251, 0, cp1251_str.c_str(), -1, &wstr[0], size_w);
    int size_u8 = WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), -1, nullptr, 0, nullptr, nullptr);
    std::string utf8_str(size_u8, 0);
    WideCharToMultiByte(CP_UTF8, 0, wstr.c_str(), -1, &utf8_str[0], size_u8, nullptr, nullptr);
    return utf8_str;
}

// Конвертация UTF-8 → CP1251 с проверкой
static std::string utf8_to_cp1251(const std::string& utf8_str) {
    if (utf8_str.empty()) return "";
    
    // Проверяем, содержит ли строка только ASCII (цифры и латиница)
    bool is_ascii = true;
    for (char c : utf8_str) {
        if ((unsigned char)c > 127) {
            is_ascii = false;
            break;
        }
    }
    
    if (is_ascii) {
        return utf8_str; // ASCII одинаков в UTF-8 и CP1251
    }
    
    // Для кириллицы конвертируем
    int size_w = MultiByteToWideChar(CP_UTF8, 0, utf8_str.c_str(), -1, nullptr, 0);
    if (size_w == 0) {
        std::cerr << "[C++] Ошибка UTF-8→UTF16 для: " << utf8_str << std::endl;
        return utf8_str;
    }
    
    std::wstring wstr(size_w, 0);
    MultiByteToWideChar(CP_UTF8, 0, utf8_str.c_str(), -1, &wstr[0], size_w);
    
    int size_cp = WideCharToMultiByte(1251, 0, wstr.c_str(), -1, nullptr, 0, nullptr, nullptr);
    if (size_cp == 0) {
        std::cerr << "[C++] Ошибка UTF16→CP1251" << std::endl;
        return utf8_str;
    }
    
    std::string cp1251_str(size_cp, 0);
    WideCharToMultiByte(1251, 0, wstr.c_str(), -1, &cp1251_str[0], size_cp, nullptr, nullptr);
    
    return cp1251_str;
}

void search_in_file(const std::wstring& filepath_w, const std::string& target, int request_id) {
    HANDLE hFile = CreateFileW(
        filepath_w.c_str(), GENERIC_READ, FILE_SHARE_READ, NULL,
        OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN, NULL
    );

    if (hFile == INVALID_HANDLE_VALUE) return;

    const DWORD BUF_SIZE = 10 * 1024 * 1024; 
    char* buf = new char[BUF_SIZE];
    std::string leftover;
    int match_count = 0;
    int line_number = 1;

    while (true) {
        DWORD bytesRead = 0;
        if (!ReadFile(hFile, buf, BUF_SIZE, &bytesRead, NULL) || bytesRead == 0) break;

        std::string data = leftover + std::string(buf, bytesRead);
        leftover.clear();

        size_t start = 0;
        size_t end = 0;
        
        while ((end = data.find('\n', start)) != std::string::npos) {
            std::string line = data.substr(start, end - start);
            if (!line.empty() && line.back() == '\r') {
                line.pop_back();
            }

            // Конвертируем строку из CP1251 в UTF-8 для поиска
            std::string line_utf8 = cp1251_to_utf8(line);
            
            // Ищем в UTF-8 версии строки
            if (line_utf8.find(target) != std::string::npos) {
                match_count++;

                if (g_callback) {
                    g_callback(request_id, 1,
                               wstring_to_utf8(filepath_w).c_str(),
                               line_utf8.c_str(),
                               line_number,
                               0.0);
                }
            }

            line_number++;
            start = end + 1;
        }

        if (start < data.length()) {
            leftover = data.substr(start);
        }
    }

    delete[] buf;
    CloseHandle(hFile);
}

EXPORT void search_init() { g_callback = nullptr; }

EXPORT int search_start(
    const char** filepaths,
    int file_count,
    const char* target_number,
    SearchResultCallback callback) {
    
    g_callback = callback;
    std::string target(target_number);
    
    std::cout << "[C++] Поиск: '" << target << "'" << std::endl;
    
    int request_id = 1;

    for (int i = 0; i < file_count; i++) {
        int size = MultiByteToWideChar(CP_UTF8, 0, filepaths[i], -1, nullptr, 0);
        std::wstring filepath_w(size, 0);
        MultiByteToWideChar(CP_UTF8, 0, filepaths[i], -1, &filepath_w[0], size);
        
        search_in_file(filepath_w, target, request_id);
    }

    return request_id;
}

EXPORT void search_cancel(int) {}
EXPORT void search_cleanup() { g_callback = nullptr; }