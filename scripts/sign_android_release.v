// Combine trusted unsigned CI APKs and sign with the private release identity.
module main

import os
import rand
import compress.szip
import crypto.sha256

fn command(program string, args []string) ! {
	mut process := os.new_process(program)
	process.set_args(args)
	process.run()
	process.wait()
	code := process.code
	process.close()
	if code != 0 {
		return error('${program} failed (${code})')
	}
}

fn archive_entries(path string) !map[string][]u8 {
	mut archive := szip.open(path, .no_compression, .read_only)!
	defer { archive.close() }
	mut entries := map[string][]u8{}
	for index in 0 .. archive.total()! {
		archive.open_entry_by_index(index)!
		name := archive.name()
		if name.ends_with('/') || name.starts_with('META-INF/') {
			archive.close_entry()
			continue
		}
		if name.starts_with('/') || name.split('/').contains('..') {
			return error('Invalid archive path: ${name}')
		}
		mut data := []u8{len: int(archive.size())}
		archive.read_entry_buf(data.data, data.len)!
		entries[name] = data
		archive.close_entry()
	}
	return entries
}

fn main() {
	run() or {
		eprintln(err)
		exit(1)
	}
}

fn run() ! {
	mut inputs := []string{}
	mut options := map[string]string{}
	mut index := 1
	for index < os.args.len {
		if index + 1 >= os.args.len {
			return error('Missing value for ${os.args[index]}')
		}
		flag := os.args[index]
		value := os.args[index + 1]
		if flag == '--input' {
			inputs << value
		} else {
			options[flag] = value
		}
		index += 2
	}
	for key in ['--output', '--build-tools', '--keystore', '--password-file'] {
		if options[key] == '' {
			return error('Missing ${key}')
		}
	}
	if inputs.len != 3 {
		return error('Provide the three ABI input directories with --input')
	}
	abis := ['armeabi-v7a', 'arm64-v8a', 'x86_64']
	mut common_entries := map[string][]u8{}
	mut libraries := map[string][]u8{}
	mut notices := map[string][]u8{}
	for position, folder in inputs {
		entries := archive_entries(os.join_path(folder, 'vimgui-demo-unsigned.apk'))!
		mut common := map[string][]u8{}
		for name, bytes in entries {
			if name.starts_with('lib/') {
				parts := name.split('/')
				if parts.len != 3 || parts[1] !in abis || !parts[2].ends_with('.so') {
					return error('Unexpected native library: ${name}')
				}
				if name in libraries {
					return error('Duplicate native input: ${name}')
				}
				libraries[name] = bytes
			} else {
				common[name] = bytes
			}
		}
		if position == 0 {
			common_entries = common.clone()
		} else if common_entries != common {
			return error('ABI inputs disagree on the manifest, UI classes or assets')
		}
		license_dir := os.join_path(folder, 'licenses')
		if !os.is_dir(license_dir) {
			return error('Missing redistribution notices: ${license_dir}')
		}
		for file in os.walk_ext(license_dir, '') {
			if !os.is_file(file) {
				continue
			}
			name := 'assets/licenses/' + file.trim_string_left(license_dir + os.path_separator).replace('\\', '/')
			bytes := os.read_bytes(file)!
			if name in notices && notices[name] != bytes {
				return error('License inputs disagree: ${name}')
			}
			notices[name] = bytes
		}
	}
	for abi in abis {
		for name in ['libvimgui.so', 'libvimgui_android_demo.so', 'libvimgui_android_ui.so'] {
			if 'lib/${abi}/${name}' !in libraries {
				return error('Incomplete ABI: ${abi}')
			}
		}
	}
	if libraries.len != 9 {
		return error('Unexpected extra native libraries')
	}
	os.mkdir_all(options['--output'])!
	temporary := os.join_path(os.temp_dir(), 'v-imgui-sign-' + rand.uuid_v4())
	os.mkdir(temporary, mode: 0o700)!
	defer { os.rmdir_all(temporary) or {} }
	for variant in ['universal', 'armeabi-v7a', 'arm64-v8a', 'x86_64'] {
		unsigned := os.join_path(temporary, 'unsigned.apk')
		aligned := os.join_path(temporary, 'aligned.apk')
		output := os.join_path(options['--output'], 'v-imgui-touch-${variant}.apk')
		mut contents := common_entries.clone()
		for name, bytes in notices {
			contents[name] = bytes
		}
		for name, bytes in libraries {
			if variant == 'universal' || name.split('/')[1] == variant {
				contents[name] = bytes
			}
		}
		mut archive := szip.open(unsigned, .best_compression, .write)!
		mut names := contents.keys()
		names.sort()
		for name in names {
			archive.open_entry(name)!
			archive.write_entry(contents[name])!
			archive.close_entry()
		}
		archive.close()
		command(os.join_path(options['--build-tools'], 'zipalign'), ['-f', '-p', '4', unsigned,
			aligned])!
		alias := if options['--alias'] != '' { options['--alias'] } else { 'v-imgui-release' }
		password := 'file:' + options['--password-file']
		command(os.join_path(options['--build-tools'], 'apksigner'), ['sign', '--ks',
			options['--keystore'], '--ks-key-alias', alias, '--ks-pass', password, '--key-pass',
			password, '--out', output, aligned])!
		command(os.join_path(options['--build-tools'], 'apksigner'), ['verify', '--verbose', output])!
		println('${sha256.hexhash(os.read_file(output)!)}  ${os.file_name(output)}')
	}
}
