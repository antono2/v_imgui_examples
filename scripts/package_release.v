#!/usr/bin/env -S v -prod run
// Packages prepared desktop binaries for the docking or standard variant.
// Delegates dependency collection, notices, archive creation, and checksums to release_tools.

module main

import os
import release_tools

fn main() {
	if os.args.len != 5 {
		eprintln('Usage: ./scripts/package_release.v binary-dir imgui-dir output-dir docking|standard')
		exit(2)
	}
	release_tools.package_release(os.dir(os.dir(@FILE)), os.args[1], os.args[2], os.args[3], os.args[4]) or {
		eprintln(err)
		exit(1)
	}
}
