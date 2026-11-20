// Run package tools with argument vectors and stream their output to the caller.
module releaseconsumer

import os

pub fn run_tool(program string, args []string) ! {
	path := os.find_abs_path_of_executable(program)!
	mut child := os.new_process(path)
	defer { child.close() }
	child.set_args(args)
	child.run()
	child.wait()
	if child.code != 0 {
		return error('${program} exited with status ${child.code}')
	}
}
