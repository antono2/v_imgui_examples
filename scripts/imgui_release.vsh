#!/usr/bin/env -S v run

// Read the shared desktop/Android dependency pin from the V module manifest.
import os
import v.vmod

fn imgui_release() !string {
	root := os.dir(os.dir(os.real_path(@FILE)))
	manifest := vmod.from_file(os.join_path(root, 'v.mod'))!
	dependencies := manifest.dependencies.filter(it.starts_with('antono2.imgui@'))
	if dependencies.len != 1 {
		return error('v.mod must pin exactly one antono2.imgui release')
	}
	tag := dependencies[0].all_after('@')
	if !tag.starts_with('v') || tag.len < 2 || !tag.bytes().all((it >= `0` && it <= `9`)
		|| (it >= `a` && it <= `z`) || (it >= `A` && it <= `Z`) || it in [`.`, `-`, `_`]) {
		return error('Invalid ImGui release tag in v.mod: ${tag}')
	}
	return tag
}

fn main() {
	println(imgui_release() or {
		eprintln(err)
		exit(1)
	})
}
