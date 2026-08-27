cmake_minimum_required(VERSION 3.21)
project(RuntimePackNetFx35Enabler LANGUAGES CXX)

add_executable(RuntimePack.NetFx35Enabler NetFx35Enabler.cpp)
target_compile_features(RuntimePack.NetFx35Enabler PRIVATE cxx_std_20)
target_compile_definitions(RuntimePack.NetFx35Enabler PRIVATE UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
# The helper runs before any optional VC++ redistributable package in the chain.
# Keep the C and C++ runtimes inside it so that NetFx3 can be enabled on a clean OS.
set_target_properties(RuntimePack.NetFx35Enabler PROPERTIES
    WIN32_EXECUTABLE TRUE
    MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
