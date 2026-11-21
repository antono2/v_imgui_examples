// Build or check all desktop examples with the selected V compiler.
import os
import release_tools

const usage = 'Usage: v run scripts/build_desktop.vsh --output DIRECTORY [V flags...]\n       v run scripts/build_desktop.vsh --check [V flags...]'

fn run(args []string) ! {
	if args in [['--help'], ['-h']] {
		println(usage)
		return
	}
	root := os.dir(@DIR)
	if args.len >= 1 && args[0] == '--check' {
		release_tools.compile_desktop(@VEXE, root, '', args[1..])!
	} else if args.len >= 2 && args[0] == '--output' && args[1] != '' {
		release_tools.compile_desktop(@VEXE, root, os.abs_path(args[1]), args[2..])!
	} else {
		return error(usage)
	}
}

run(os.args[1..]) or {
	eprintln(err.msg())
	exit(1)
}
