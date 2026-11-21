// Render the desktop examples on Lavapipe and retain the Vulkan diagnostics.
import desktopsettings
import os
import strings
import time

const initial_diagnostics_capacity = 256
const example_timeout = 60 * time.second
const capture_interval = 10 * time.millisecond

fn render(xvfb string, binary string, args []string, environment map[string]string, log_path string) ! {
	if !os.is_executable(binary) {
		return error('Expected an executable at ${binary}')
	}
	mut log_file := os.create(log_path)!
	defer { log_file.close() }
	mut process := os.new_process(xvfb)
	mut command := ['-a', binary]
	command << args
	process.set_args(command)
	process.set_environment(environment)
	process.set_redirect_stdio()
	process.use_pgroup = true
	process.run()
	defer { process.close() }
	mut output := strings.new_builder(initial_diagnostics_capacity)
	timer := time.new_stopwatch()
	for {
		live := process.is_alive()
		text := process.stdout_read() + process.stderr_read()
		if text != '' {
			output.write_string(text)
			log_file.write_string(text)!
			log_file.flush()
		}
		if !live && text == '' {
			process.wait()
			break
		}
		if timer.elapsed() >= example_timeout {
			if live {
				process.signal_pgkill()
				process.wait()
			}
			return error('Rendering timed out. See ${log_path}')
		}
		if text == '' {
			time.sleep(capture_interval)
		}
	}
	diagnostics := output.str()
	print(diagnostics)
	lower := diagnostics.to_lower_ascii()
	if process.code != 0 || ['vuid-', 'validation error', 'segmentation', 'assert', 'fatal'].any(lower.contains(it)) {
		return error('Rendering failed with exit status ${process.code}. See ${log_path}')
	}
}

fn run(args []string) ! {
	usage := 'Usage: v run scripts/smoke_desktop.vsh BINARY_DIRECTORY'
	if args in [['-h'], ['--help']] {
		println(usage)
		return
	}
	if args.len != 1 {
		return error(usage)
	}
	root := os.abs_path(args[0])
	if !os.is_dir(root) {
		return error('Missing binary directory: ${root}')
	}
	xvfb := os.find_abs_path_of_executable('xvfb-run')!
	logs := os.join_path(root, 'smoke-logs')
	os.mkdir_all(logs)!
	mut manifests := os.glob('/usr/share/vulkan/icd.d/lvp_icd*.json')!
	manifests.sort()
	if manifests.len == 0 || !os.is_file(manifests[0]) {
		return error('No Lavapipe driver manifest in /usr/share/vulkan/icd.d')
	}
	mut environment := os.environ()
	environment['VK_DRIVER_FILES'] = manifests[0]
	environment['VK_ICD_FILENAMES'] = manifests[0]
	environment['VK_INSTANCE_LAYERS'] = 'VK_LAYER_KHRONOS_validation'
	menu := os.join_path(root, 'examples')
	for example in ['glfw_vulkan', 'widget_gallery', 'implot_dashboard'] {
		frames := if example == 'implot_dashboard' {
			desktopsettings.dashboard_smoke_frames
		} else {
			desktopsettings.standard_smoke_frames
		}
		environment['VIMGUI_SMOKE_FRAMES'] = frames.str()
		log_path := os.join_path(logs, example + '.log')
		if os.is_executable(menu) {
			render(xvfb, menu, [example], environment, log_path)!
		} else {
			render(xvfb, os.join_path(root, example), [], environment, log_path)!
		}
		println('Rendered and shut down: ${example} (${frames} frames)')
	}
}

run(os.args[1..]) or {
	eprintln(err)
	exit(1)
}
