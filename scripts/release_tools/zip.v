// Writes ZIP32 archives for desktop packages and Android signing inputs.
// Preserves entry permissions and fixed timestamps while rejecting archives beyond ZIP32 limits.
module release_tools

import os
import compress.deflate
import hash.crc32

struct ZipEntry {
	name       string
	crc        u32
	compressed u32
	original   u32
	offset     u32
	mode       u32
}

pub struct ZipWriter {
mut:
	file    os.File
	offset  u64
	entries []ZipEntry
}

fn le16(mut bytes []u8, value u16) {
	bytes << u8(value)
	bytes << u8(value >> 8)
}

fn le32(mut bytes []u8, value u32) {
	for shift in [0, 8, 16, 24] {
		bytes << u8(value >> shift)
	}
}

pub fn new_zip(path string) !ZipWriter {
	return ZipWriter{ file: os.create(path)! }
}

pub fn (mut zip ZipWriter) close() {
	zip.file.close()
}

fn (mut zip ZipWriter) write(bytes []u8) ! {
	if zip.offset + u64(bytes.len) >= 0xffffffff {
		return error('ZIP32 archive exceeds 4 GiB')
	}
	written := zip.file.write(bytes)!
	if written != bytes.len {
		return error('Incomplete ZIP write')
	}
	zip.offset += u64(written)
}

// APK tools require ZIP32. szip's writer always emits ZIP64, so share this
// small writer between APK signing and desktop packages. Fixed DOS timestamps
// avoid invalid dates from source archives and make entry metadata reproducible.
pub fn (mut zip ZipWriter) add(name string, bytes []u8, mode u32) ! {
	if name == '' || name.starts_with('/') || name.contains('\\') || name.split('/').contains('..') || name.len > 65535 {
		return error('Invalid ZIP entry: ${name}')
	}
	if zip.entries.len >= 65535 || u64(bytes.len) >= 0xffffffff {
		return error('ZIP32 limit exceeded')
	}
	compressed := deflate.compress(bytes, format: .raw_deflate)!
	entry := ZipEntry{ name: name, crc: crc32.sum(bytes), compressed: u32(compressed.len), original: u32(bytes.len), offset: u32(zip.offset), mode: mode }
	mut header := []u8{}
	le32(mut header, 0x04034b50)
	le16(mut header, 20)
	le16(mut header, 0x0800)
	le16(mut header, 8)
	le16(mut header, 0)
	le16(mut header, 0x0021)
	le32(mut header, entry.crc)
	le32(mut header, entry.compressed)
	le32(mut header, entry.original)
	le16(mut header, u16(name.len))
	le16(mut header, 0)
	header << name.bytes()
	zip.write(header)!
	zip.write(compressed)!
	zip.entries << entry
}

pub fn (mut zip ZipWriter) finish() ! {
	central_offset := u32(zip.offset)
	for entry in zip.entries {
		mut header := []u8{}
		le32(mut header, 0x02014b50)
		le16(mut header, 0x0314)
		le16(mut header, 20)
		le16(mut header, 0x0800)
		le16(mut header, 8)
		le16(mut header, 0)
		le16(mut header, 0x0021)
		le32(mut header, entry.crc)
		le32(mut header, entry.compressed)
		le32(mut header, entry.original)
		le16(mut header, u16(entry.name.len))
		le16(mut header, 0)
		le16(mut header, 0)
		le16(mut header, 0)
		le16(mut header, 0)
		le32(mut header, entry.mode << 16)
		le32(mut header, entry.offset)
		header << entry.name.bytes()
		zip.write(header)!
	}
	central_size := u32(zip.offset) - central_offset
	mut end := []u8{}
	le32(mut end, 0x06054b50)
	le16(mut end, 0)
	le16(mut end, 0)
	le16(mut end, u16(zip.entries.len))
	le16(mut end, u16(zip.entries.len))
	le32(mut end, central_size)
	le32(mut end, central_offset)
	le16(mut end, 0)
	zip.write(end)!
}

pub fn zip_folder(folder string, archive string) ! {
	mut zip := new_zip(archive)!
	defer { zip.close() }
	mut files := os.walk_ext(folder, '')
	files.sort()
	for file in files {
		if !os.is_file(file) {
			continue
		}
		relative := file.trim_string_left(folder + os.path_separator).replace('\\', '/')
		info := os.stat(file)!
		zip.add(os.file_name(folder) + '/' + relative, os.read_bytes(file)!, u32(0o100000) | (info.mode & 0o777))!
	}
	zip.finish()!
}

pub fn zip_entries(path string, entries map[string][]u8) ! {
	mut zip := new_zip(path)!
	defer { zip.close() }
	mut names := entries.keys()
	names.sort()
	for name in names {
		zip.add(name, entries[name], 0o100644)!
	}
	zip.finish()!
}
