@echo off
setlocal

:: odin-slug build script (Windows)
:: Builds examples and optionally checks the library.

if "%1"=="" goto check
if "%1"=="check" goto check
if "%1"=="opengl" goto opengl
if "%1"=="raylib" goto raylib
if "%1"=="vulkan" goto vulkan
if "%1"=="shaders" goto shaders
if "%1"=="all" goto all
if "%1"=="clean" goto clean
if "%1"=="help" goto usage
goto unknown

:usage
echo Usage: build.bat [command]
echo.
echo Commands:
echo   check       Check that all packages compile (no binary output)
echo   opengl      Build the OpenGL/GLFW demo
echo   raylib      Build the Raylib integration demo
echo   vulkan      Compile shaders + build the Vulkan/SDL3 demo
echo   shaders     Compile GLSL 4.50 shaders to SPIR-V (requires glslc)
echo   all         Build all examples
echo   clean       Remove build artifacts
echo.
echo If no command is given, 'check' is run.
goto :eof

:check
echo === Checking core library ===
odin check slug\ -no-entry-point
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
echo Core: OK

echo === Checking OpenGL backend ===
odin check slug\backends\opengl\ -no-entry-point
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
echo OpenGL backend: OK

echo === Checking Vulkan backend ===
odin check slug\backends\vulkan\ -no-entry-point
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
echo Vulkan backend: OK

echo.
echo All packages compile cleanly.
goto :eof

:shaders
echo === Compiling shaders ===
glslc slug\shaders\slug_450.vert -o slug\shaders\slug_vert.spv
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
glslc slug\shaders\slug_450.frag -o slug\shaders\slug_frag.spv
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
echo Shaders compiled.
goto :eof

:opengl
echo === Building OpenGL demo ===
odin build examples\demo_opengl\ -out:demo_opengl.exe -collection:libs=.
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
echo Built: demo_opengl.exe
goto :eof

:raylib
echo === Building Raylib demo ===
odin build examples\demo_raylib\ -out:demo_raylib.exe -collection:libs=.
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
echo Built: demo_raylib.exe
goto :eof

:vulkan
call :shaders
echo === Building Vulkan demo ===
odin build examples\demo_vulkan\ -out:demo_vulkan.exe -collection:libs=.
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%
echo Built: demo_vulkan.exe
goto :eof

:all
call :opengl
call :raylib
call :vulkan
goto :eof

:clean
echo === Cleaning build artifacts ===
del /f /q demo_opengl.exe demo_raylib.exe demo_vulkan.exe 2>nul
del /f /q slug\shaders\slug_vert.spv slug\shaders\slug_frag.spv 2>nul
echo Clean.
goto :eof

:unknown
echo Unknown command: %1
goto usage
