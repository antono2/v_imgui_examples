// Run package tools with argument vectors and stream their output to the caller.
module releaseconsumer

import os

pub fn run_tool(program string, args []string) ! {
	path := os.find_abs_path_of_executable(program)!
	if !os.is_file(path) {
		return error('Executable is missing: ${path}')
	}
	mut child := os.new_process(os.real_path(path))
	defer { child.close() }
	child.set_args(args)
	child.run()
	child.wait()
	if child.code != 0 {
		return error('${program} exited with status ${child.code}')
	}
}
