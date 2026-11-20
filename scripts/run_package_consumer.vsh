// Download or run one desktop package using the same consumer as release CI.
import os
import rand
import scripts.releaseconsumer

const project = 'antono2/v_imgui_examples'
const checksum_name = 'SHA256SUMS.txt'
const runtime_image = 'ubuntu:24.04'

fn download(directory string, archive string) ! {
	tag := os.getenv('RELEASE_TAG')
	mut args := ['release', 'download', '--repo', project, '--pattern', archive, '--pattern',
		checksum_name, '--dir', directory]
	if tag != '' && tag != 'latest' {
		if tag.starts_with('-') {
			return error('Invalid release tag: ${tag}')
		}
		args << tag
	}
	releaseconsumer.run_tool('gh', args)!
}

fn consume_linux(downloads string, logs string, archive string, checksums bool) ! {
	stage := os.join_path(os.temp_dir(), 'imgui-consumer-' + rand.uuid_v4())
	os.mkdir(stage, mode: 0o700)!
	defer { os.rmdir_all(stage) or { eprintln(err) } }
	binary := 'test-release-package'
	source := os.join_path(@DIR, 'test_release_package.vsh')
	releaseconsumer.run_tool(@VEXE, ['-cc', 'gcc', '-skip-running', '-o', os.join_path(stage, binary),
		source])!
	// Mount only the consumer executable, release inputs and writable diagnostics.
	mut args := ['run', '--rm', '--init', '-v', '${stage}:/runner:ro', '-v',
		'${downloads}:/downloads:ro', '-v', '${logs}:/logs', runtime_image, '/runner/' + binary,
		'--ubuntu-runtime', '/downloads/' + archive, '--project', 'imgui', '--logs', '/logs']
	if checksums {
		args << ['--checksums', '/downloads/' + checksum_name]
	}
	releaseconsumer.run_tool('docker', args)!
}

fn consume(platform string, directory string, archive string, checksums bool) ! {
	if platform != os.user_os() {
		return error('Run the ${platform} consumer on a ${platform} host')
	}
	path := os.join_path(directory, archive)
	sum := os.join_path(directory, checksum_name)
	if !os.is_file(path) {
		return error('Package archive is missing: ${path}')
	}
	if checksums && !os.is_file(sum) {
		return error('Package checksums are missing: ${sum}')
	}
	logs := os.abs_path('package-smoke-logs')
	os.mkdir_all(logs)!
	if platform == 'linux' {
		return consume_linux(directory, logs, archive, checksums)
	}
	mut args := ['run', os.join_path(@DIR, 'test_release_package.vsh'), path, '--project', 'imgui',
		'--logs', logs]
	if checksums {
		args << ['--checksums', sum]
	}
	releaseconsumer.run_tool(@VEXE, args)!
}

fn run(args []string) ! {
	usage := 'Usage: v run scripts/run_package_consumer.vsh download|test linux|windows docking|standard [--checksums]\nDownloads are located in downloads/. Set RELEASE_TAG for a specific published release.'
	if args in [['--help'], ['-h']] {
		println(usage)
		return
	}
	if args.len !in [3, 4] || args[0] !in ['download', 'test']
		|| args[1] !in ['linux', 'windows'] || args[2] !in ['docking', 'standard']
		|| (args.len == 4 && (args[0] != 'test' || args[3] != '--checksums')) {
		return error(usage)
	}
	directory := os.abs_path('downloads')
	archive := 'v-imgui-examples-${args[1]}-x64-${args[2]}.zip'
	if args[0] == 'download' {
		return download(directory, archive)
	}
	consume(args[1], directory, archive, args.len == 4)!
}

run(os.args[1..]) or {
	eprintln(err)
	exit(1)
}
