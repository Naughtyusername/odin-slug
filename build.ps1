$ErrorActionPreference = "Stop"

# odin-slug build script (PowerShell)
# Builds examples and optionally checks the library.

param(
    [string]$Command = "check"
)

function Do-Check {
    Write-Host "=== Checking core library ==="
    odin check slug/ -no-entry-point
    Write-Host "Core: OK"

    Write-Host "=== Checking OpenGL backend ==="
    odin check slug/backends/opengl/ -no-entry-point
    Write-Host "OpenGL backend: OK"

    Write-Host "=== Checking Raylib backend ==="
    odin check slug/backends/raylib/ -no-entry-point
    Write-Host "Raylib backend: OK"

    Write-Host "=== Checking Vulkan backend ==="
    odin check slug/backends/vulkan/ -no-entry-point
    Write-Host "Vulkan backend: OK"

    Write-Host ""
    Write-Host "All packages compile cleanly."
}

function Do-CompileShaders {
    Write-Host "=== Compiling shaders ==="
    glslc slug/shaders/slug_450.vert -o slug/shaders/slug_vert.spv
    glslc slug/shaders/slug_450.frag -o slug/shaders/slug_frag.spv
    Write-Host "Shaders compiled."
}

function Do-BuildOpenGL {
    Write-Host "=== Building OpenGL demo ==="
    odin build examples/demo_opengl/ -out:demo_opengl.exe -collection:libs=.
    Write-Host "Built: demo_opengl.exe"
}

function Do-BuildRaylib {
    Write-Host "=== Building Raylib demo ==="
    odin build examples/demo_raylib/ -out:demo_raylib.exe -collection:libs=.
    Write-Host "Built: demo_raylib.exe"
}

function Do-BuildVulkan {
    Do-CompileShaders
    Write-Host "=== Building Vulkan demo ==="
    odin build examples/demo_vulkan/ -out:demo_vulkan.exe -collection:libs=.
    Write-Host "Built: demo_vulkan.exe"
}

function Do-Clean {
    Write-Host "=== Cleaning build artifacts ==="
    Remove-Item -Force -ErrorAction SilentlyContinue demo_opengl.exe, demo_raylib.exe, demo_vulkan.exe
    Remove-Item -Force -ErrorAction SilentlyContinue slug/shaders/slug_vert.spv, slug/shaders/slug_frag.spv
    Write-Host "Clean."
}

switch ($Command) {
    "check"   { Do-Check }
    "opengl"  { Do-BuildOpenGL }
    "raylib"  { Do-BuildRaylib }
    "vulkan"  { Do-BuildVulkan }
    "shaders" { Do-CompileShaders }
    "all"     { Do-BuildOpenGL; Do-BuildRaylib; Do-BuildVulkan }
    "clean"   { Do-Clean }
    "help"    {
        Write-Host "Usage: .\build.ps1 [command]"
        Write-Host ""
        Write-Host "Commands:"
        Write-Host "  check       Check that all packages compile (no binary output)"
        Write-Host "  opengl      Build the OpenGL/GLFW demo"
        Write-Host "  raylib      Build the Raylib integration demo"
        Write-Host "  vulkan      Compile shaders + build the Vulkan/SDL3 demo"
        Write-Host "  shaders     Compile GLSL 4.50 shaders to SPIR-V (requires glslc)"
        Write-Host "  all         Build all examples"
        Write-Host "  clean       Remove build artifacts"
    }
    default {
        Write-Host "Unknown command: $Command"
        Write-Host "Run: .\build.ps1 help"
    }
}
