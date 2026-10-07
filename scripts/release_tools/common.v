// Shared process execution and file helpers for release tooling.
// Runs commands with argument vectors to preserve paths and literal linker values.
module release_tools

import os

fn executable(program string) !string {
	if os.is_file(program) {
		return os.real_path(program)
	}
	$if windows {
		if os.is_abs_path(program) || program.contains('/') || program.contains('\\') {
			for suffix in ['.exe', '.bat', '.cmd'] {
				if os.is_file(program + suffix) {
					return os.real_path(program + suffix)
				}
			}
			return error('Executable not found: ${program}')
		}
	}
	return os.find_abs_path_of_executable(program)
}

// Argument vectors keep paths and literal RPATH values out of a shell parser.
pub fn command(program string, args []string) ! {
	mut process := os.new_process(executable(program)!)
	process.set_args(args)
	process.run()
	process.wait()
	code := process.code
	process.close()
	if code != 0 {
		return error('${program} failed (${code})')
	}
}

pub fn capture(program string, args []string) !(int, string) {
	mut process := os.new_process(executable(program)!)
	process.set_args(args)
	process.set_redirect_stdio_merged()
	process.run()
	output := process.stdout_slurp()
	process.wait()
	code := process.code
	process.close()
	return code, output
}

pub fn checked_output(program string, args []string) !string {
	code, output := capture(program, args)!
	if code != 0 {
		return error('${program} failed (${code}): ${output}')
	}
	return output
}

pub fn copy(source string, destination string) ! {
	os.mkdir_all(os.dir(destination))!
	os.cp(os.real_path(source), destination)!
}
