#!/bin/bash
set -e

# odin-slug build script
# Builds examples and optionally checks the library.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

usage() {
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  check       Check that all packages compile (no binary output)"
    echo "  opengl      Build the OpenGL/GLFW demo"
    echo "  raylib      Build the Raylib integration demo"
    echo "  vulkan      Compile shaders + build the Vulkan/SDL3 demo"
    echo "  sdl3gpu     Compile shaders + build the SDL3 GPU demo"
    echo "  shaders     Compile GLSL 4.50 shaders to SPIR-V (requires glslc)"
    echo "  all         Build all examples"
    echo "  clean       Remove build artifacts"
    echo ""
    echo "If no command is given, 'check' is run."
}

do_check() {
    echo "=== Checking core library ==="
    odin check slug/ -no-entry-point
    echo "Core: OK"

    echo "=== Checking OpenGL backend ==="
    odin check slug/backends/opengl/ -no-entry-point
    echo "OpenGL backend: OK"

    echo "=== Checking Raylib backend ==="
    odin check slug/backends/raylib/ -no-entry-point
    echo "Raylib backend: OK"

    echo "=== Checking Vulkan backend ==="
    odin check slug/backends/vulkan/ -no-entry-point
    echo "Vulkan backend: OK"

    echo "=== Checking SDL3 GPU backend ==="
    odin check slug/backends/sdl3gpu/ -no-entry-point
    echo "SDL3 GPU backend: OK"

    echo ""
    echo "All packages compile cleanly."
}

do_compile_shaders() {
    echo "=== Compiling shaders ==="
    # Vulkan backend (push_constant)
    glslc slug/shaders/slug_450.vert -o slug/shaders/slug_vert.spv
    glslc slug/shaders/slug_450.frag -o slug/shaders/slug_frag.spv
    glslc slug/shaders/rect_450.vert -o slug/shaders/rect_vert.spv
    glslc slug/shaders/rect_450.frag -o slug/shaders/rect_frag.spv
    # SDL3 GPU backend (UBO uniforms)
    glslc slug/shaders/slug_sdl3.vert -o slug/shaders/slug_sdl3_vert.spv
    glslc slug/shaders/slug_sdl3.frag -o slug/shaders/slug_sdl3_frag.spv
    glslc slug/shaders/rect_sdl3.vert -o slug/shaders/rect_sdl3_vert.spv
    echo "Shaders compiled."
}

do_build_opengl() {
    echo "=== Building OpenGL demo ==="
    odin build examples/demo_opengl/ -out:demo_opengl -collection:libs=.
    echo "Built: ./demo_opengl"
}

do_build_raylib() {
    echo "=== Building Raylib demo ==="
    odin build examples/demo_raylib/ -out:demo_raylib -collection:libs=.
    echo "Built: ./demo_raylib"
}

do_build_vulkan() {
    do_compile_shaders
    echo "=== Building Vulkan demo ==="
    odin build examples/demo_vulkan/ -out:demo_vulkan -collection:libs=.
    echo "Built: ./demo_vulkan"
}

do_build_sdl3gpu() {
    do_compile_shaders
    echo "=== Building SDL3 GPU demo ==="
    odin build examples/demo_sdl3gpu/ -out:demo_sdl3gpu -collection:libs=.
    echo "Built: ./demo_sdl3gpu"
}

do_clean() {
    echo "=== Cleaning build artifacts ==="
    rm -f demo_opengl demo_raylib demo_vulkan demo_sdl3gpu
    rm -f slug/shaders/slug_vert.spv slug/shaders/slug_frag.spv
    echo "Clean."
}

CMD="${1:-check}"

case "$CMD" in
    check)   do_check ;;
    opengl)  do_build_opengl ;;
    raylib)  do_build_raylib ;;
    vulkan)  do_build_vulkan ;;
    sdl3gpu) do_build_sdl3gpu ;;
    shaders) do_compile_shaders ;;
    all)     do_build_opengl; do_build_raylib; do_build_vulkan; do_build_sdl3gpu ;;
    clean)   do_clean ;;
    help|-h) usage ;;
    *)       echo "Unknown command: $CMD"; usage; exit 1 ;;
esac
