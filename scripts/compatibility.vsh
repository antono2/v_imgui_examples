// Resolve and verify the compiler, SDK, and module pins used by the examples.
import flag
import os
import rand
import x.json2

const immutable_fields = ['v', 'vc', 'tcc', 'linux_vc', 'linux_tcc', 'headers', 'volk', 'v3_v',
	'v3_vc']
const required_fields = ['v', 'vc', 'modules', 'glfw', 'ci_sdk', 'ci_runtime']

@[params]
pub struct Profile {
pub:
	platform string
	variant  string = 'docking'
	compiler string = 'stable'
}

fn name_is_safe(name string) bool {
	return name != '' && name.bytes().all((it >= `a` && it <= `z`) || it.is_digit() || it == `_`)
}

fn release_is_valid(version string) bool {
	parts := version.split('.')
	return parts.len == 3 && parts.all(it != '' && it.bytes().all(it.is_digit()))
}

fn pin_value(pins map[string]json2.Any, key string) string {
	value := pins[key] or { return '' }
	return if value is string { value } else { '' }
}

fn verify_project_pins(root string, modules map[string]json2.Any) ! {
	quoted := os.read_file(os.join_path(root, 'v.mod'))!.split("'")
	for index := 1; index < quoted.len; index += 2 {
		value := quoted[index]
		if value.starts_with('antono2.') && value.contains('@') {
			name, declared := value['antono2.'.len..].split_once('@') or { continue }
			if name_is_safe(name) && pin_value(modules, name) != declared {
				return error('v.mod and compatibility.json disagree for ${name}: ${declared}')
			}
		}
	}
}

fn resolve(root string, options Profile) !map[string]string {
	host := if os.user_os() == 'windows' { 'windows' } else { 'linux' }
	platform := if options.platform == '' { host } else { options.platform }
	if platform !in ['windows', 'linux'] || options.variant !in ['docking', 'standard']
		|| options.compiler !in ['stable', 'v3'] {
		return error('invalid platform, variant, or compiler profile')
	}
	pins :=
		json2.decode[map[string]json2.Any](os.read_file(os.join_path(root, 'compatibility.json'))!)!
	if (pins['schema_version'] or { json2.Any(0) }).int() != 1 {
		return error('Unsupported compatibility schema_version')
	}
	for key in immutable_fields {
		if key in pins {
			commit := pin_value(pins, key)
			if commit.len != 40 || !commit.bytes().all(it.is_digit() || (it >= `a` && it <= `f`)) {
				return error('${key} must be an immutable Git commit')
			}
		}
	}
	for key in required_fields {
		if key != 'modules' && pin_value(pins, key) == '' {
			return error('Missing compatibility field: ${key}')
		}
	}
	modules_value := pins['modules'] or { return error('Missing compatibility field: modules') }
	if modules_value !is map[string]json2.Any {
		return error('Missing compatibility field: modules')
	}
	modules := modules_value.as_map()
	if modules.len == 0 {
		return error('Missing compatibility field: modules')
	}
	mut outputs := map[string]string{}
	for key, value in pins {
		if value is string {
			outputs[key] = value
		}
	}
	verify_project_pins(root, modules)!
	for name, value in modules {
		tag := value.str()
		version := tag.trim_string_right('-standard')
		if !name_is_safe(name) || !version.starts_with('v') || !release_is_valid(version[1..]) {
			return error('Invalid module pin: ${name}=${tag}')
		}
		outputs['module_' + name] = tag
	}
	if platform == 'linux' {
		for key in ['vc', 'tcc'] {
			if selected := outputs['linux_' + key] {
				outputs[key] = selected
			}
		}
	}
	if options.variant == 'standard' && 'module_imgui' in outputs {
		tag := outputs['imgui_standard'] or { '' }
		version := tag.trim_string_right('-standard')
		if !tag.ends_with('-standard') || !version.starts_with('v')
			|| !release_is_valid(version[1..]) {
			return error('imgui_standard must be an exact standard release tag')
		}
		outputs['module_imgui'] = tag
	}
	if options.compiler == 'v3' {
		for key in ['v', 'vc'] {
			outputs[key] = outputs['v3_' + key] or { return error('V3 profile requires v3_${key}') }
		}
	}
	for key, value in outputs {
		if !name_is_safe(key) || value.contains_any('\r\n') {
			return error('Unsafe compatibility output: ${key}')
		}
	}
	return outputs
}

fn revision(checkout string, ref string) !string {
	result := os.exec(['git', '-C', checkout, 'rev-parse', '--verify', ref])
	if result.exit_code != 0 {
		return error('could not resolve ${ref} in ${checkout}: ${result.output.trim_space()}')
	}
	return result.output.trim_space()
}

fn verify_modules(outputs map[string]string, modules string) ! {
	for key, tag in outputs {
		if !key.starts_with('module_') {
			continue
		}
		name := key['module_'.len..]
		checkout := os.join_path(modules, 'antono2', name)
		if revision(checkout, 'HEAD')! != revision(checkout, 'refs/tags/${tag}^{commit}')! {
			return error('Installed ${name} does not match ${tag}: ${checkout}')
		}
	}
}

fn self_test(root string) ! {
	windows := resolve(root, platform: 'windows')!
	linux := resolve(root, platform: 'linux')!
	assert windows['v'] == linux['v']
	assert linux['vc'] == (windows['linux_vc'] or { windows['vc'] })
	standard := resolve(root, platform: 'linux', variant: 'standard', compiler: 'v3')!
	assert standard['module_imgui'] == linux['imgui_standard']
	assert standard['v'] == linux['v3_v'] && standard['vc'] == linux['v3_vc']
	work := os.join_path(os.temp_dir(), 'imgui-compat-' + rand.uuid_v4())
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	project := os.join_path(work, 'v.mod')
	manifest := os.join_path(work, 'compatibility.json')
	os.cp(os.join_path(root, 'v.mod'), project)!
	manifest_source := os.read_file(os.join_path(root, 'compatibility.json'))!
	mut altered := json2.decode[map[string]json2.Any](manifest_source)!
	altered['imgui_standard'] = json2.Any('v99.0.0-standard')
	os.write_file(manifest, json2.encode(altered))!
	bumped := resolve(work, platform: 'linux', variant: 'standard')!
	unaffected := resolve(work, platform: 'linux')!
	assert bumped['module_imgui'] == 'v99.0.0-standard'
	assert unaffected['module_imgui'] == linux['module_imgui']
	altered['imgui_standard'] = json2.Any('master')
	os.write_file(manifest, json2.encode(altered))!
	mut refused_standard := false
	resolve(work, variant: 'standard') or {
		if !err.msg().contains('exact standard release') {
			return err
		}
		refused_standard = true
		map[string]string{}
	}
	assert refused_standard
	os.write_file(manifest, manifest_source)!
	os.write_file(project, "Module { dependencies: ['antono2.imgui@v99.0.0'] }")!
	resolve(work, platform: 'windows') or {
		if !err.msg().contains('disagree') {
			return err
		}
		println('Compatibility pins and refusal checks passed.')
		return
	}
	return error('compatibility accepted a mismatched module pin')
}

fn run(args []string) ! {
	mut parser := flag.new_flag_parser(args)
	parser.application('compatibility')
	parser.description('Validate and resolve tested build pins.')
	root := parser.string('root', 0, os.dir(@DIR), 'project root')
	platform := parser.string('platform', 0, '', 'windows or linux, defaults to the current host')
	variant := parser.string('variant', 0, 'docking', 'docking or standard')
	compiler := parser.string('compiler', 0, 'stable', 'stable or v3')
	output_path := parser.string('github-output', 0, '', 'append pins to this GitHub output file')
	key := parser.string('get', 0, '', 'print a single pin')
	modules := parser.string('modules', 0, '', 'verify module checkouts')
	test := parser.bool('self-test', 0, false,
		'check pin resolution and reject a dependency mismatch')
	if parser.bool('help', `h`, false, 'show help') {
		println(parser.usage())
		return
	}
	if parser.finalize()!.len != 0 {
		return error('unexpected positional arguments')
	}
	if test {
		self_test(root)!
		return
	}
	outputs := resolve(root, platform: platform, variant: variant, compiler: compiler)!
	if modules != '' {
		verify_modules(outputs, modules)!
	}
	if output_path != '' {
		mut output := os.open_append(output_path)!
		defer { output.close() }
		for name, value in outputs {
			output.writeln('${name}=${value}')!
		}
	}
	if key != '' {
		println(outputs[key] or { return error('unknown compatibility output: ${key}') })
	} else {
		println(json2.encode(outputs, prettify: true))
	}
}

run(os.args[1..]) or {
	eprintln(err)
	exit(1)
}
