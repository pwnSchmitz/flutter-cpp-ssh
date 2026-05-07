cmake_minimum_required(VERSION 3.15)
project(search_engine LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS ON)

# Добавляем исходный файл
add_library(search_engine SHARED
    search_engine.cpp
)

# Компилируем с поддержкой Unicode (для Windows API)
target_compile_definitions(search_engine PRIVATE _UNICODE UNICODE)

# Автоматически копируем DLL в корень проекта Flutter после сборки
if(WIN32)
    add_custom_command(TARGET search_engine POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy
        $<TARGET_FILE:search_engine>
        ${CMAKE_SOURCE_DIR}/../search_engine.dll)
endif()