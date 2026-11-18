// Exercise standard release selection and actual commit checks with isolated Git fixtures.
import os
import rand

const module_name = 'antono2.imgui'
const docking_tag = 'v0.3.1'
const independent_standard_tag = 'v0.4.0-standard'

fn git(module_dir string, args []string) ! {
	mut command := ['git', '-C', module_dir]
	command << args
	result := os.exec(command)
	if result.exit_code != 0 {
		return error('Git fixture setup failed: ${command}\n${result.output}')
	}
}

fn commit(module_dir string, message string) ! {
	git(module_dir, ['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit',
		'--allow-empty', '-qm', message])!
}

fn check(compiler string, script string, args []string, succeeds bool, expected string) ! {
	mut command := [compiler, 'run', script]
	command << args
	result := os.exec(command)
	if (result.exit_code == 0) != succeeds || !result.output.contains(expected) {
		return error('Unexpected result for ${args} (exit ${result.exit_code})\n${result.output}')
	}
}

fn run() ! {
	if os.args.len != 1 {
		return error('Usage: v run scripts/test_installed_deps.vsh')
	}
	root := os.join_path(os.temp_dir(), 'imgui-dependency-fixture-' + rand.uuid_v4())
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	script := os.join_path(root, 'scripts', 'check_installed_deps.vsh')
	os.mkdir(os.dir(script))!
	os.cp(os.join_path(@DIR, 'check_installed_deps.vsh'), script)!
	os.write_file(os.join_path(root, 'v.mod'),
		"Module { dependencies: ['${module_name}@${docking_tag}'] }")!

	modules := os.join_path(root, 'modules')
	module_dir := os.join_path(modules, 'antono2', 'imgui')
	os.mkdir_all(module_dir)!
	os.write_file(os.join_path(module_dir, 'v.mod'), "Module { name: '${module_name}' }")!
	git(module_dir, ['init', '-q'])!
	git(module_dir, ['add', 'v.mod'])!
	commit(module_dir, 'fixture')!
	git(module_dir, ['tag', docking_tag + '-standard'])!
	git(module_dir, ['tag', independent_standard_tag])!

	compiler := os.getenv_opt('V_BIN') or { @VEXE }
	os.setenv('VMODULES', modules, true)
	// An explicit V_BIN may select a different installation from the one running this script.
	os.unsetenv('VEXE')
	override := ['--tag-override', '${module_name}=${independent_standard_tag}']
	suffix := ['--tag-suffix', '${module_name}=-standard']
	check(compiler, script, override, true, 'Verified ${module_name}@${independent_standard_tag}')!
	check(compiler, script, suffix, true, 'Verified ${module_name}@${docking_tag}-standard')!
	mut conflicting := suffix.clone()
	conflicting << override
	check(compiler, script, conflicting, false, 'repeated tag selection')!
	mut unused := suffix.clone()
	unused << ['--tag-override', 'antono2.typo=${independent_standard_tag}']
	check(compiler, script, unused, false, 'did not match a dependency')!
	commit(module_dir, 'different head')!
	check(compiler, script, override, false, 'does not match')!
	println('Installed dependency fixture passed release selection and refusal checks.')
}

run() or {
	eprintln(err)
	exit(1)
}
