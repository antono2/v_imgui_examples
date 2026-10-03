module main

import os
import release_tools

fn main() {
	if os.args.len !in [3, 4] || (os.args.len == 4 && os.args[3] != 'android') {
		eprintln('Usage: v run scripts/collect_licenses.v imgui-dir output-dir [android]')
		exit(2)
	}
	release_tools.collect_licenses(os.dir(os.dir(@FILE)), os.args[1], os.args[2], os.args.len == 4) or {
		eprintln(err)
		exit(1)
	}
}
