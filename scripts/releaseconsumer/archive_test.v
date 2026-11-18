// Exercise archive integrity and fail-closed extraction with generated fixtures.
module releaseconsumer

import compress.gzip
import compress.szip
import crypto.sha256
import encoding.binary
import os
import rand

fn fixture() !string {
	path := os.join_path(os.temp_dir(), 'release-archive-test-' + rand.uuid_v4())
	os.mkdir(path, mode: 0o700)!
	return path
}

fn test_checksum_requires_one_matching_entry_and_intact_bytes() ! {
	work := fixture()!
	defer { os.rmdir_all(work) or {} }
	archive := os.join_path(work, 'release.zip')
	checksums := os.join_path(work, 'SHA256SUMS')
	original := 'original release'
	digest := sha256.sum(original.bytes()).hex()
	os.write_file(archive, original)!
	os.write_file(checksums, '${digest} *other.zip\n${digest} *release.zip\n')!
	verify_checksum(archive, checksums)!
	os.write_file(archive, 'modified release')!
	if _ := verify_checksum(archive, checksums) {
		assert false, 'accepted changed bytes'
	} else {
		assert err.msg().contains('Checksum mismatch')
	}
	for text in ['${digest}  other.zip\n', '${digest}  release.zip\n${digest} *release.zip\n'] {
		os.write_file(checksums, text)!
		if _ := verify_checksum(archive, checksums) {
			assert false, 'accepted missing or duplicate checksum'
		} else {
			assert err.msg().contains('exactly one')
		}
	}
}

fn put_zip(path string) ! {
	mut zip := szip.open(path, .no_compression, .write)!
	defer { zip.close() }
	for name in ['package/tool', 'package/file'] {
		zip.open_entry(name)!
		zip.write_entry('contents'.bytes())!
		zip.close_entry()
	}
}

fn put_zip_mode(mut archive []u8, directory int, mode u16) {
	binary.little_endian_put_u16_at(mut archive, mode, directory + 40)
}

fn expect_refusal(path string, output string, diagnostic string) ! {
	os.mkdir(output)!
	if _ := extract(path, output) {
		assert false, 'unsafe archive was accepted'
	} else {
		assert err.msg().contains(diagnostic), err.msg()
	}
	assert os.ls(output)!.len == 0, 'unsafe entries must be refused before extracting an earlier file'
}

fn second_zip_record(archive []u8, first int) int {
	return first + zip_central_size + int(binary.little_endian_u16_at(archive, first + 28)) +
		int(binary.little_endian_u16_at(archive, first + 30)) +
		int(binary.little_endian_u16_at(archive, first + 32))
}

fn test_zip_preserves_executability_and_preflights_types_and_paths() ! {
	work := fixture()!
	defer { os.rmdir_all(work) or {} }
	path := os.join_path(work, 'release.zip')
	put_zip(path)!
	mut bytes := os.read_bytes(path)!
	directory := zip_directory(bytes)!
	assert directory >= 0
	put_zip_mode(mut bytes, directory, 0o100755)
	os.write_file_array(path, bytes)!
	output := os.join_path(work, 'valid')
	os.mkdir(output)!
	extract(path, output)!
	tool := os.join_path(output, 'package', 'tool')
	assert os.read_file(tool)! == 'contents'
	$if !windows {
		assert os.is_executable(tool)
	}
	second := second_zip_record(bytes, directory)
	mut symlink := bytes.clone()
	put_zip_mode(mut symlink, second, 0o120777)
	os.write_file_array(path, symlink)!
	expect_refusal(path, os.join_path(work, 'bad-link'), 'Archive symlink')!
	mut traversal := bytes.clone()
	for index, octet in '../outside!!'.bytes() {
		traversal[second + zip_central_size + index] = octet
	}
	os.write_file_array(path, traversal)!
	expect_refusal(path, os.join_path(work, 'bad-path'), 'Unsafe archive path')!
}

fn tar_fixture_member(name string, kind u8, data string) []u8 {
	mut header := []u8{len: tar_block}
	for index, octet in name.bytes() {
		header[index] = octet
	}
	header[156] = kind
	copy(mut header[100..108], '0000755\0'.bytes())
	copy(mut header[124..136], '${data.len:011o}\0'.bytes())
	copy(mut header[148..156], '        '.bytes())
	copy(mut header[257..263], 'ustar\0'.bytes())
	mut checksum := 0
	for octet in header {
		checksum += int(octet)
	}
	copy(mut header[148..156], '${checksum:06o}\0 '.bytes())
	header << data.bytes()
	header << []u8{len: (tar_block - data.len % tar_block) % tar_block}
	return header
}

fn test_tar_validates_path_overrides_and_rejects_links_and_special_files() ! {
	work := fixture()!
	defer { os.rmdir_all(work) or {} }
	path := os.join_path(work, 'release.tar.gz')
	valid := tar_fixture_member('pkg/tool', `0`, 'contents')
	end := []u8{len: 2 * tar_block}
	mut archive := valid.clone()
	// The local PAX path is authoritative, including for GNU or POSIX producers.
	archive << tar_fixture_member('PaxHeader', `x`, '18 path=pkg/extra\n')
	archive << tar_fixture_member('ignored', `0`, 'other file')
	archive << end
	os.write_file_array(path, gzip.compress(archive)!)!
	output := os.join_path(work, 'valid')
	os.mkdir(output)!
	extract(path, output)!
	assert os.read_file(os.join_path(output, 'pkg', 'tool'))! == 'contents'
	assert os.read_file(os.join_path(output, 'pkg', 'extra'))! == 'other file'
	for kind in [`1`, `2`, `3`, `4`, `6`] {
		mut invalid := valid.clone()
		invalid << tar_fixture_member('pkg/bad', u8(kind), '')
		invalid << end
		os.write_file_array(path, gzip.compress(invalid)!)!
		expect_refusal(path, os.join_path(work, 'bad-kind-${kind}'), 'Unsupported archive entry')!
	}
	mut traversal := valid.clone()
	traversal << tar_fixture_member('PaxHeader', `x`, '18 path=../escape\n')
	traversal << tar_fixture_member('pkg/safe', `0`, '')
	traversal << end
	os.write_file_array(path, gzip.compress(traversal)!)!
	expect_refusal(path, os.join_path(work, 'bad-pax'), 'Unsafe archive path')!
}
