// Compile the same desktop examples for CI and portable releases.
module release_tools

import os

const examples = ['glfw_vulkan', 'widget_gallery', 'implot_dashboard']

// An empty output path runs the compiler checks without producing executables.
pub fn compile_desktop(compiler string, root string, output string, flags []string) ! {
	if output != '' {
		os.mkdir_all(output)!
	}
	extension := $if windows { '.exe' } $else { '' }
	for example in examples {
		source := if example == 'glfw_vulkan' {
			root
		} else {
			os.join_path(root, 'examples', example)
		}
		mut args := flags.clone()
		if output == '' {
			args << '-check'
		} else {
			args << ['-o', os.join_path(output, example + extension)]
		}
		args << source
		command(compiler, args) or { return error('${example}: ${err}') }
	}
}
