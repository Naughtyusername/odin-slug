@echo off
setlocal

:: odin-slug build script (Windows cmd)
:: Builds examples and optionally checks the library.
::
:: External dependency backends:
::   Karl2D:  set KARL2D_PATH=C:\path\to   (parent dir of karl2d\)
::            auto-detects ..\karl2d\ as sibling directory
::   Sokol:   set SOKOL_PATH=C:\path\to\sokol-odin\sokol
::            auto-detects ..\sokol-odin\sokol\ as sibling directory

set SCRIPT_DIR=%~dp0

if "%1"==""        goto do_check
if "%1"=="check"   goto do_check
if "%1"=="opengl"  goto do_opengl
if "%1"=="raylib"  goto do_raylib
if "%1"=="vulkan"  goto do_vulkan
if "%1"=="sdl3gpu" goto do_sdl3gpu
if "%1"=="d3d11"   goto do_d3d11
if "%1"=="karl2d"  goto do_karl2d
if "%1"=="sokol"   goto do_sokol
if "%1"=="shaders" goto do_shaders
if "%1"=="all"     goto do_all
if "%1"=="clean"   goto do_clean
if "%1"=="help"    goto usage
goto unknown

:usage
echo Usage: build.bat [command]
echo.
echo Commands:
echo   check       Check that all packages compile (no binary output)
echo   opengl      Build the OpenGL/GLFW demo
echo   raylib      Build the Raylib integration demo
echo               Note: if GL loader fails on Windows, add -define:RAYLIB_SHARED=true
echo   vulkan      Compile shaders + build the Vulkan demo
echo   sdl3gpu     Compile shaders + build the SDL3 GPU demo
echo   d3d11       Build the D3D11 demo (Windows only, no external deps)
echo   karl2d      Build the Karl2D demo (requires KARL2D_PATH or sibling ..\karl2d\)
echo   sokol       Build the Sokol GFX demo (requires SOKOL_PATH or sibling ..\sokol-odin\sokol\)
echo   shaders     Compile GLSL 4.50 + SDL3 shaders to SPIR-V (requires glslc)
echo   all         Build opengl + raylib + vulkan + sdl3gpu + d3d11
echo   clean       Remove build artifacts
echo.
echo If no command is given, 'check' is run.
goto :eof

:: --------------------------------------------------------------------------
:do_check
echo === Checking core library ===
odin check slug\ -no-entry-point
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
echo Core: OK

echo === Checking OpenGL backend ===
odin check slug\backends\opengl\ -no-entry-point
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
echo OpenGL backend: OK

echo === Checking Raylib backend ===
odin check slug\backends\raylib\ -no-entry-point
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
echo Raylib backend: OK

if exist "slug\shaders\slug_vert.spv" (
    echo === Checking Vulkan backend ===
    odin check slug\backends\vulkan\ -no-entry-point
    if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
    echo Vulkan backend: OK
) else (
    echo === Skipping Vulkan backend ^(run 'build.bat shaders' first^) ===
)

if exist "slug\shaders\slug_sdl3_vert.spv" (
    echo === Checking SDL3 GPU backend ===
    odin check slug\backends\sdl3gpu\ -no-entry-point
    if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
    echo SDL3 GPU backend: OK
) else (
    echo === Skipping SDL3 GPU backend ^(run 'build.bat shaders' first^) ===
)

echo === Checking D3D11 backend ===
odin check slug\backends\d3d11\ -no-entry-point
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
echo D3D11 backend: OK

echo === Checking Karl2D backend ===
odin check slug\backends\karl2d\ -no-entry-point
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
echo Karl2D backend: OK

:: Sokol requires its collection path
set SOKOL_CHECK_PATH=%SOKOL_PATH%
if "%SOKOL_CHECK_PATH%"=="" (
    if exist "%SCRIPT_DIR%..\sokol-odin\sokol\" (
        set SOKOL_CHECK_PATH=%SCRIPT_DIR%..\sokol-odin\sokol
    )
)
if not "%SOKOL_CHECK_PATH%"=="" (
    echo === Checking Sokol backend ===
    odin check slug\backends\sokol\ -no-entry-point -collection:sokol="%SOKOL_CHECK_PATH%"
    if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
    echo Sokol backend: OK
) else (
    echo === Skipping Sokol backend ^(SOKOL_PATH not set^) ===
)

echo.
echo All packages compile cleanly.
goto :eof

:: --------------------------------------------------------------------------
:do_shaders
echo === Compiling shaders ===
:: Vulkan backend (push_constant uniforms)
glslc slug\shaders\slug_450.vert -o slug\shaders\slug_vert.spv
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
glslc slug\shaders\slug_450.frag -o slug\shaders\slug_frag.spv
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
glslc slug\shaders\rect_450.vert -o slug\shaders\rect_vert.spv
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
glslc slug\shaders\rect_450.frag -o slug\shaders\rect_frag.spv
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
:: SDL3 GPU backend (UBO uniforms)
glslc slug\shaders\slug_sdl3.vert -o slug\shaders\slug_sdl3_vert.spv
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
glslc slug\shaders\slug_sdl3.frag -o slug\shaders\slug_sdl3_frag.spv
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
glslc slug\shaders\rect_sdl3.vert -o slug\shaders\rect_sdl3_vert.spv
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
echo Shaders compiled.
goto :eof

:: --------------------------------------------------------------------------
:do_opengl
echo === Building OpenGL demo ===
odin build examples\demo_opengl\ -out:demo_opengl.exe -collection:libs=.
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
echo Built: demo_opengl.exe
goto :eof

:do_raylib
echo === Building Raylib demo ===
odin build examples\demo_raylib\ -out:demo_raylib.exe -collection:libs=.
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
echo Built: demo_raylib.exe
echo Note: if you see NULL GL function pointers at runtime, rebuild with -define:RAYLIB_SHARED=true
goto :eof

:do_vulkan
call "%~f0" shaders
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
echo === Building Vulkan demo ===
odin build examples\demo_vulkan\ -out:demo_vulkan.exe -collection:libs=.
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
echo Built: demo_vulkan.exe
goto :eof

:do_sdl3gpu
call "%~f0" shaders
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
echo === Building SDL3 GPU demo ===
odin build examples\demo_sdl3gpu\ -out:demo_sdl3gpu.exe -collection:libs=.
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
echo Built: demo_sdl3gpu.exe
goto :eof

:do_d3d11
echo === Building D3D11 demo ===
odin build examples\demo_d3d11\ -out:demo_d3d11.exe -collection:libs=.
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
echo Built: demo_d3d11.exe
goto :eof

:do_karl2d
echo === Building Karl2D demo ===
set KARL2D_BUILD_PATH=%KARL2D_PATH%
if "%KARL2D_BUILD_PATH%"=="" (
    if exist "%SCRIPT_DIR%..\karl2d\" (
        set KARL2D_BUILD_PATH=%SCRIPT_DIR%..
    ) else (
        echo Error: KARL2D_PATH not set and ..\karl2d\ not found.
        echo   Clone it:  git clone https://github.com/nicoepp/karl2d ..\karl2d
        echo   Or set:    set KARL2D_PATH=C:\path\to   ^(parent dir of karl2d\^)
        exit /b 1
    )
)
odin build examples\demo_karl2d\ -out:demo_karl2d.exe -collection:libs=. -collection:karl2d="%KARL2D_BUILD_PATH%"
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
echo Built: demo_karl2d.exe
goto :eof

:do_sokol
echo === Building Sokol GFX demo ===
set SOKOL_BUILD_PATH=%SOKOL_PATH%
if "%SOKOL_BUILD_PATH%"=="" (
    if exist "%SCRIPT_DIR%..\sokol-odin\sokol\" (
        set SOKOL_BUILD_PATH=%SCRIPT_DIR%..\sokol-odin\sokol
    ) else (
        echo Error: SOKOL_PATH not set and ..\sokol-odin\sokol\ not found.
        echo   Clone it:  git clone https://github.com/floooh/sokol-odin ..\sokol-odin
        echo             cd ..\sokol-odin\sokol ^&^& build_clibs_windows.cmd
        echo   Or set:    set SOKOL_PATH=C:\path\to\sokol-odin\sokol
        exit /b 1
    )
)
odin build examples\demo_sokol\ -out:demo_sokol.exe -collection:libs=. -collection:sokol="%SOKOL_BUILD_PATH%"
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
echo Built: demo_sokol.exe
goto :eof

:: --------------------------------------------------------------------------
:do_all
call "%~f0" opengl
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
call "%~f0" raylib
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
call "%~f0" vulkan
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
call "%~f0" sdl3gpu
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
call "%~f0" d3d11
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
goto :eof

:do_clean
echo === Cleaning build artifacts ===
del /f /q demo_opengl.exe demo_raylib.exe demo_vulkan.exe demo_sdl3gpu.exe demo_d3d11.exe demo_karl2d.exe demo_sokol.exe 2>nul
del /f /q slug\shaders\*.spv 2>nul
echo Clean.
goto :eof

:: --------------------------------------------------------------------------
:unknown
echo Unknown command: %1
goto usage
