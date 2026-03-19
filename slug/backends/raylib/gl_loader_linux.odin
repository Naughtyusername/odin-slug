#+build linux, darwin, freebsd, openbsd
package slug_raylib

import "core:sys/posix"

// Raylib loads libGL at runtime via dlopen without RTLD_GLOBAL,
// so GL symbols aren't visible to dlsym(RTLD_DEFAULT). We load
// libGL ourselves with RTLD_GLOBAL to make them discoverable,
// then use glXGetProcAddress for extension functions.

@(private = "package")
gl_lib: posix.Symbol_Table

@(private = "package")
glx_get_proc: proc "c" (name: cstring) -> rawptr

@(private = "package")
gl_loader_init :: proc() {
	if gl_lib != nil do return

	// Try common GL library names — libGL.so.1 covers most Linux systems
	lib_names := [?]cstring{"libGL.so.1", "libGL.so", "libOpenGL.so.0"}
	for lib_name in lib_names {
		gl_lib = posix.dlopen(lib_name, {.NOW, .GLOBAL})
		if gl_lib != nil do break
	}

	if gl_lib != nil {
		glx_get_proc = auto_cast posix.dlsym(gl_lib, "glXGetProcAddressARB")
	}
}

@(private = "package")
get_gl_proc :: proc(name: cstring) -> rawptr {
	if gl_lib == nil do gl_loader_init()

	// Try glXGetProcAddress first — it handles extension functions
	// that may not be exported as regular symbols
	if glx_get_proc != nil {
		addr := glx_get_proc(name)
		if addr != nil do return addr
	}

	// Fallback to dlsym on the GL library
	if gl_lib != nil {
		return posix.dlsym(gl_lib, name)
	}

	return nil
}
