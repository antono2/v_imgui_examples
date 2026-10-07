// Release-package launcher that selects a desktop example by argument or menu.
// Locates bundled executables relative to the launcher and forwards their arguments.
module main

import os

fn main() {
	choices := ['widget_gallery', 'implot_dashboard', 'glfw_vulkan']
	mut example := if os.args.len > 1 { os.args[1] } else { '' }
	if example in ['--help', '-h'] {
		println('Usage: examples [widget_gallery|implot_dashboard|glfw_vulkan] [example arguments]')
		return
	}
	if example == '' {
		println('V ImGui examples\n\n1. Widget gallery — controls, accessibility and virtual lists (default)\n2. ImPlot dashboard — interactive plots and rolling history\n3. GLFW/Vulkan — windows, docking and backend demonstration\nQ. Quit\n')
		answer := os.input_opt('Choose an example [1]: ') or { return }
		match answer.trim_space().to_lower() {
			'', '1' { example = choices[0] }
			'2' { example = choices[1] }
			'3' { example = choices[2] }
			'q' { return }
			else {
				eprintln('Choose 1, 2, 3 or Q.')
				exit(2)
			}
		}
	}
	if example !in choices {
		eprintln('Unknown example: ${example}. Use --help for choices.')
		exit(2)
	}
	mut filename := example
	$if windows {
		filename += '.exe'
	}
	path := os.join_path(os.dir(os.executable()), filename)
	if !os.is_file(path) {
		eprintln('Could not find ${filename}. Extract the entire release archive and keep its files together.')
		exit(1)
	}
	mut child := os.new_process(path)
	child.set_args(if os.args.len > 2 { os.args[2..] } else { []string{} })
	child.run()
	child.wait()
	code := child.code
	child.close()
	if code != 0 {
		eprintln('${example} could not run (exit ${code}). Check that the whole archive is extracted and your graphics driver supports Vulkan.')
		if os.is_atty(0) != 0 { os.input('Press Enter to close. ') }
	}
	exit(code)
}
