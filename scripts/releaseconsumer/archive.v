// Validate paths and member types before unpacking downloaded release archives.
module releaseconsumer

import compress.gzip
import compress.szip
import crypto.sha256
import encoding.binary
import os
import strconv

const archive_limit = 512 * 1024 * 1024
const checksum_block = 1024 * 1024
const zip_end_size = 22
const zip_comment_limit = 65_535
const zip_central_size = 46
const tar_block = 512

struct Member {
	name      string
	directory bool
	mode      int
	start     int
	size      int
}

pub fn verify_checksum(archive string, checksums string) ! {
	mut entries := []string{}
	for line in os.read_lines(checksums)! {
		if line.len <= 64 || !line[64].is_space() || !line[..64].bytes().all(it.is_hex_digit()) {
			continue
		}
		if line[64..].trim_left(' \t').trim_string_left('*') == os.file_name(archive) {
			entries << line[..64].to_lower_ascii()
		}
	}
	if entries.len != 1 {
		return error('Expected exactly one checksum for ${os.file_name(archive)}')
	}
	mut digest := sha256.new()
	mut file := os.open(archive)!
	defer { file.close() }
	mut buffer := []u8{len: checksum_block}
	for {
		count := file.read(mut buffer) or {
			if err is os.Eof {
				break
			}
			return err
		}
		if count == 0 {
			break
		}
		digest.write(buffer[..count])!
	}
	if digest.sum([]u8{}).hex() != entries[0] {
		return error('Checksum mismatch: ${os.file_name(archive)}')
	}
}

fn member_name(name string) !string {
	if name == '' || name.starts_with('/') || name.contains_any('\\:\r\n\0') {
		return error('Unsafe archive path: ${name}')
	}
	mut parts := []string{}
	for part in name.split('/') {
		if part in ['', '.'] {
			continue
		}
		base := part.all_before('.').to_upper_ascii()
		if part.ends_with('.') || part.ends_with(' ') || base in ['CON', 'PRN', 'AUX', 'NUL', 'COM1',
			'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9', 'LPT1', 'LPT2', 'LPT3',
			'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9'] {
			return error('Unsafe archive path: ${name}')
		}
		parts << part
	}
	return parts.join('/')
}

fn check_member(mut seen map[string]bool, member Member) ! {
	if member.name == '' && !member.directory {
		return error('Unsafe empty file path')
	}
	key := if os.user_os() == 'windows' { member.name.to_lower() } else { member.name }
	if directory := seen[key] {
		if !directory || !member.directory {
			return error('Duplicate archive path: ${member.name}')
		}
	}
	seen[key] = member.directory
}

fn zip_directory(data []u8) !int {
	mut end := data.len - zip_end_size
	earliest := if end > zip_comment_limit { end - zip_comment_limit } else { 0 }
	for end >= earliest {
		if data[end..end + 4] == [u8(0x50), 0x4b, 5, 6]
			&& int(binary.little_endian_u16_at(data, end + 20)) == data.len - end - zip_end_size {
			if binary.little_endian_u16_at(data, end + 4) != 0
				|| binary.little_endian_u16_at(data, end + 6) != 0 {
				return error('Multi-volume ZIP archives are unsupported')
			}
			size := binary.little_endian_u32_at(data, end + 12)
			has_locator := end >= 20 && binary.little_endian_u32_at(data, end - 20) == 0x07064b50
			if has_locator || size == 0xffffffff || binary.little_endian_u32_at(data, end + 16) == 0xffffffff
				|| binary.little_endian_u16_at(data, end + 10) == 0xffff {
				if !has_locator || end < 76 {
					return error('Invalid ZIP64 end record')
				}
				record := binary.little_endian_u64_at(data, end - 12)
				if record > u64(end - 76) || binary.little_endian_u32_at(data, int(record)) != 0x06064b50 {
					return error('Invalid ZIP64 end record')
				}
				wide_size := binary.little_endian_u64_at(data, int(record) + 40)
				if wide_size > record {
					return error('Invalid ZIP64 directory size')
				}
				return int(record - wide_size)
			}
			if size > u32(end) {
				return error('Invalid ZIP directory size')
			}
			return end - int(size)
		}
		end--
	}
	return -1
}

fn zip_members(data []u8, directory int, count int) ![]Member {
	mut members := []Member{cap: count}
	mut seen := map[string]bool{}
	mut offset := directory
	for _ in 0 .. count {
		if offset > data.len - zip_central_size
			|| binary.little_endian_u32_at(data, offset) != 0x02014b50 {
			return error('Invalid ZIP central directory entry')
		}
		name_len := int(binary.little_endian_u16_at(data, offset + 28))
		extra_len := int(binary.little_endian_u16_at(data, offset + 30))
		comment_len := int(binary.little_endian_u16_at(data, offset + 32))
		attributes := binary.little_endian_u32_at(data, offset + 38)
		start := offset + zip_central_size
		offset = start + name_len + extra_len + comment_len
		if offset > data.len {
			return error('Truncated ZIP central directory entry')
		}
		mode := int(attributes >> 16)
		raw := data[start..start + name_len].bytestr()
		name := member_name(raw)!
		file_type := mode & 0o170000
		if file_type == 0o120000 {
			return error('Archive symlink: ${raw}')
		}
		if file_type !in [0, 0o100000, 0o040000] {
			return error('Unsupported archive entry: ${raw}')
		}
		member := Member{
			name:      name
			directory: raw.ends_with('/') || file_type == 0o040000 || attributes & 0x10 != 0
			mode:      mode
		}
		check_member(mut seen, member)!
		members << member
	}
	return members
}

fn write_member(destination string, member Member, data []u8) ! {
	path := os.join_path(destination, ...member.name.split('/'))
	if member.directory {
		os.mkdir_all(path)!
		return
	}
	os.mkdir_all(os.dir(path))!
	os.write_file_array(path, data)!
	$if !windows {
		mode := if member.mode & 0o111 != 0 { 0o755 } else { 0o644 }
		os.chmod(path, mode)!
	}
}

fn extract_zip(archive string, data []u8, directory int, destination string) ! {
	mut zip := szip.open(archive, .no_compression, .read_only)!
	defer { zip.close() }
	members := zip_members(data, directory, zip.total()!)!
	mut total := u64(0)
	for index, member in members {
		zip.open_entry_by_index(index)!
		defer { zip.close_entry() }
		if member.name != member_name(zip.name())! {
			return error('ZIP directory name mismatch')
		}
		if member.directory {
			write_member(destination, member, [])!
			continue
		}
		size := zip.size()
		if size > archive_limit - total {
			return error('Expanded archive exceeds ${archive_limit} bytes')
		}
		total += size
		mut bytes := []u8{len: int(size)}
		if bytes.len > 0 && zip.read_entry_buf(bytes.data, bytes.len)! != bytes.len {
			return error('Truncated ZIP entry: ${member.name}')
		}
		write_member(destination, member, bytes)!
	}
}

fn tar_text(data []u8) string {
	return data.bytestr().all_before('\0')
}

fn tar_number(data []u8) !u64 {
	// GNU tar may encode large nonnegative sizes in base 256.
	if data[0] == 0x80 {
		mut result := u64(0)
		for octet in data[1..] {
			if result > (max_u64 >> 8) {
				return error('Tar number exceeds 64 bits')
			}
			result = (result << 8) | octet
		}
		return result
	}
	text := tar_text(data).trim_space()
	return if text == '' { u64(0) } else { strconv.parse_uint(text, 8, 64)! }
}

fn pax_fields(data []u8) !map[string]string {
	mut result := map[string]string{}
	mut offset := 0
	for offset < data.len {
		space := data[offset..].index(` `)
		if space < 0 {
			return error('Invalid PAX record length')
		}
		length := strconv.atoi(data[offset..offset + space].bytestr())!
		if length <= space + 2 || length > data.len - offset || data[offset + length - 1] != `\n` {
			return error('Invalid PAX record length')
		}
		key, value := data[offset + space + 1..offset + length - 1].bytestr().split_once('=') or {
			return error('Invalid PAX record')
		}
		if key.starts_with('GNU.sparse') || key == 'linkpath' {
			return error('Unsupported TAR metadata: ${key}')
		}
		result[key] = value
		offset += length
	}
	return result
}

fn tar_members(data []u8) ![]Member {
	mut result := []Member{}
	mut seen := map[string]bool{}
	mut global := map[string]string{}
	mut local := map[string]string{}
	mut long_name := ''
	mut offset := 0
	for offset <= data.len - tar_block {
		header := data[offset..offset + tar_block]
		if header.all(it == 0) {
			return result
		}
		mut checksum := u64(0)
		for index, octet in header {
			checksum += if index >= 148 && index < 156 { u64(` `) } else { u64(octet) }
		}
		if tar_number(header[148..156])! != checksum {
			return error('Invalid TAR header checksum')
		}
		kind := header[156]
		metadata := kind in [`x`, `g`, `L`]
		mut size := tar_number(header[124..136])!
		if !metadata {
			size_value := local['size'] or { global['size'] }
			if size_value != '' {
				size = strconv.parse_uint(size_value, 10, 64)!
			}
		}
		start := offset + tar_block
		if size > u64(data.len - start) {
			return error('Truncated TAR body')
		}
		offset = start + (int(size) + tar_block - 1) / tar_block * tar_block
		if metadata {
			body := data[start..start + int(size)]
			match kind {
				`x` { local = pax_fields(body)! }
				`g` { global = pax_fields(body)! }
				else { long_name = tar_text(body) }
			}
			continue
		}
		name := tar_text(header[..100])
		prefix := if header[257..263] == [u8(`u`), `s`, `t`, `a`, `r`, 0] {
			tar_text(header[345..500])
		} else {
			''
		}
		fallback := if long_name != '' {
			long_name
		} else if prefix == '' {
			name
		} else {
			'${prefix}/${name}'
		}
		raw := local['path'] or { global['path'] or { fallback } }
		if kind !in [u8(0), `0`, `5`] {
			return error('Unsupported archive entry: ${raw}')
		}
		member := Member{
			name:      member_name(raw)!
			directory: kind == `5`
			mode:      int(tar_number(header[100..108])! & 0o777)
			start:     start
			size:      int(size)
		}
		check_member(mut seen, member)!
		result << member
		local.clear()
		long_name = ''
	}
	return error('Missing TAR end marker')
}

struct ExpandedTar {
mut:
	bytes []u8
	over  bool
}

fn append_tar(chunk []u8, user voidptr) int {
	mut expanded := unsafe { &ExpandedTar(user) }
	if chunk.len > archive_limit - expanded.bytes.len {
		expanded.over = true
		return 0
	}
	expanded.bytes << chunk
	return chunk.len
}

// extract handles ZIP, TAR and gzip-compressed TAR release packages.
pub fn extract(archive string, destination string) ! {
	if os.file_size(archive) > archive_limit {
		return error('Archive exceeds ${archive_limit} bytes')
	}
	data := os.read_bytes(archive)!
	directory := zip_directory(data)!
	if directory >= 0 {
		extract_zip(archive, data, directory, destination)!
		return
	}
	mut expanded := ExpandedTar{}
	if data.len >= 2 && data[0] == 0x1f && data[1] == 0x8b {
		gzip.decompress_with_callback(data, append_tar, &expanded)!
		if expanded.over {
			return error('Expanded archive exceeds ${archive_limit} bytes')
		}
	} else {
		expanded.bytes = data.clone()
	}
	members := tar_members(expanded.bytes)!
	for member in members {
		write_member(destination, member, expanded.bytes[member.start..member.start + member.size])!
	}
}
