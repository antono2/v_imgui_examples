module release_tools

import os

// Argument vectors keep paths and literal RPATH values out of a shell parser.
pub fn command(program string, args []string) ! {
	mut process := os.new_process(program)
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
	mut process := os.new_process(program)
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
