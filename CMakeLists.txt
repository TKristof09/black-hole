cmake_minimum_required(VERSION 3.24 FATAL_ERROR)
project(VulkanTemplate VERSION 0.1.0)

include(FetchContent)

set(SLANG_ENABLE_SLANGC OFF)
set(SLANG_ENABLE_SLANGI OFF)
set(SLANG_ENABLE_SLANGD OFF)
set(SLANG_ENABLE_TESTS OFF)
set(SLANG_ENABLE_EXAMPLES OFF)

set( CMAKE_EXPORT_COMPILE_COMMANDS ON)

add_executable(VulkanTemplate src/main.cpp)



set_property(TARGET VulkanTemplate PROPERTY CXX_STANDARD 23)
set_property(TARGET VulkanTemplate PROPERTY STANDARD_REQUIRED ON)


# set( CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/build/${CMAKE_SYSTEM_NAME}/bin)
# set( CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/build/${CMAKE_SYSTEM_NAME}/lib)
# set( CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/build/${CMAKE_SYSTEM_NAME}/lib)

set (CMAKE_VS_JUST_MY_CODE_DEBUGGING ON)

add_subdirectory(vulkan-framework)


set(GCC_CLANG_WARNINGS
    -Wall
    -Wextra
    -Wpedantic
)

set(MSVC_WARNINGS
    /W4
)

target_compile_options(VulkanFramework PRIVATE
    $<$<CXX_COMPILER_ID:GNU,Clang>:${GCC_CLANG_WARNINGS}>

    $<$<CXX_COMPILER_ID:MSVC>:${MSVC_WARNINGS}>
)

target_link_libraries(VulkanTemplate PRIVATE VulkanFramework)
