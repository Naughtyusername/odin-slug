#+build windows
package slug_raylib

import win32 "core:sys/windows"

// wglGetProcAddress handles GL 1.2+ extension functions.
// For GL 1.0/1.1 core functions it returns NULL, so we
// fall back to GetProcAddress on opengl32.dll.
@(private = "package")
get_gl_proc :: proc(name: cstring) -> rawptr {
	func := win32.wglGetProcAddress(name)
	if uintptr(func) <= 3 || func == rawptr(~uintptr(0)) {
		lib := win32.LoadLibraryW(win32.L("opengl32.dll"))
		if lib != nil {
			return rawptr(win32.GetProcAddress(lib, name))
		}
		return nil
	}
	return func
}
