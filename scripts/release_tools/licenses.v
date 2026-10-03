module release_tools

import os

// Keep the source's permission notices, including embedded component notices.
fn source_comments(source string) !string {
	mut result := []string{}
	mut offset := 0
	for offset < source.len {
		begin := source[offset..].index('/*') or { break }
		start := offset + begin
		end := source[start + 2..].index('*/') or { return error('Unclosed source comment') }
		offset = start + 2 + end + 2
		result << source[start..offset]
	}
	return result.join('\n\n') + '\n'
}

pub fn collect_licenses(root string, imgui string, output string, android bool) ! {
	files := {
		'examples.txt':      os.join_path(root, 'LICENSE')
		'imgui-v.txt':       os.join_path(imgui, 'LICENSE')
		'imgui.txt':         os.join_path(imgui, 'cimgui', 'imgui', 'LICENSE.txt')
		'cimgui.txt':        os.join_path(imgui, 'cimgui', 'LICENSE')
		'implot.txt':        os.join_path(imgui, 'cimplot', 'implot', 'LICENSE')
		'cimplot.txt':       os.join_path(imgui, 'cimplot', 'LICENSE')
		'proggy.txt':        os.join_path(root, 'packaging', 'PROGGY-LICENSE.txt')
		'proggyforever.txt': os.join_path(root, 'packaging', 'PROGGYFOREVER-LICENSE.txt')
		'v.txt':             os.join_path(@VEXEROOT, 'LICENSE')
	}
	os.mkdir_all(output)!
	for name, source in files {
		copy(source, os.join_path(output, name))!
	}
	if android {
		freetype := os.join_path(imgui, 'third_party', 'freetype')
		for name, source in {
			'roboto.txt':           os.join_path(root, 'packaging', 'ROBOTO-LICENSE.txt')
			'freetype-license.txt': os.join_path(freetype, 'LICENSE.TXT')
			'freetype-FTL.txt':     os.join_path(freetype, 'docs', 'FTL.TXT')
			'freetype-dlg.txt':     os.join_path(freetype, 'subprojects', 'dlg', 'LICENSE')
		} {
			copy(source, os.join_path(output, name))!
		}
		zlib := os.read_file(os.join_path(freetype, 'src', 'gzip', 'zlib.h'))!
		end := zlib.index('*/') or { return error('Missing FreeType zlib notice') }
		os.write_file(os.join_path(output, 'freetype-zlib.txt'), zlib[..end + 2] + '\n')!
		os.write_file(os.join_path(output, 'freetype-attribution.txt'), 'This app includes FreeType 2.13.3. Portions of this software are copyright\n© 2024 The FreeType Project (www.freetype.org). All rights reserved.\nFreeType is redistributed under the FreeType License (FTL).\n')!
	} else {
		gc_source := os.read_file(os.join_path(@VEXEROOT, 'thirdparty', 'libgc', 'gc.c'))!
		os.write_file(os.join_path(output, 'boehm-gc-notices.txt'), source_comments(gc_source)!)!
		copy(os.join_path(@VEXEROOT, 'thirdparty', 'libatomic_ops', 'LICENSE'), os.join_path(output, 'libatomic-ops.txt'))!
	}
}
