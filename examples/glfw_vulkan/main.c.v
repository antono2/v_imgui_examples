module glfw_vulkan

import antono2.vulkan as vk
import antono2.glfw
import antono2.imgui
import antono2.imgui.impl_vulkan
import antono2.imgui.impl_glfw

fn C.v_imgui_example_enable_default_navigation()

fn C.v_imgui_example_framerate() f32

fn C.v_imgui_example_draw_data_is_minimized(draw_data &imgui.ImDrawData) bool

fn C.v_imgui_example_smoke_frame_limit() int

// Hosts own Vulkan and GLFW; examples supply a frame callback and persistent state.
pub fn main() {
	mut state := DemoState{}
	run(Options{ title: 'V ImGui: GLFW + Vulkan' }, draw_demo, &state)
}

pub struct Options {
pub:
	title      string
	initialize fn (voidptr) = no_lifecycle_hook
	shutdown   fn (voidptr) = no_lifecycle_hook
}

fn no_lifecycle_hook(_ voidptr) {}

pub fn run(options Options, frame fn (mut App, voidptr), state voidptr) {
	// The binding owns Volk initialization and TinyCC's Linux loader isolation.
	if vk.initialize_loader() != vk.Result.success {
		panic('Could not initialize Vulkan loader')
	}
	glfw.set_error_callback(glfw_error_callback)
	if !glfw.initialize() {
		panic('Could not initialize GLFW')
	}

	// Create window with Vulkan context
	glfw.window_hint(glfw.client_api, glfw.no_api)

	main_scale := f32(1.0)
	window := glfw.create_windowed(i32(1200 * main_scale), i32(800 * main_scale), options.title) or {
		panic(err)
	}

	if !glfw.vulkan_supported() {
		panic('GLFW: Vulkan Not Supported')
	}

	mut app := App{}

	mut extensions := []&char{}
	mut extensions_count := u32(0)
	glfw_extensions := glfw.get_required_instance_extensions(&extensions_count)
	for i in 0 .. extensions_count {
		unsafe { extensions << glfw_extensions[i] }
	}

	app.setup_vulkan(mut extensions)

	// Create Window Surface
	mut surface := unsafe { nil }
	mut res := glfw.create_window_surface(app.instance, window, app.allocator, &surface)
	assert res == vk.Result.success

	// Create Framebuffers
	initial_size := glfw.framebuffer_size(window)
	mut wd := &app.main_window_data
	app.setup_vulkan_window(mut wd, surface, initial_size.width, initial_size.height)

	// Setup Dear ImGui context
	mut ig_ctx := imgui.create_context(unsafe { nil })
	imgui.get_io_context_ptr(ig_ctx)
	// Enable keyboard and gamepad controls.
	C.v_imgui_example_enable_default_navigation()
	app.docking_available = imgui.configure_docking(true)
	// Setup Dear ImGui style
	imgui.style_colors_dark(unsafe { nil })

	// Setup scaling
	mut style := imgui.get_style()
	// Bake a fixed style scale. (until we have a solution for dynamic style scaling, changing this requires resetting Style + calling this again)
	imgui.style_scale_all_sizes(style, main_scale)

	// Setup Platform/Renderer backends
	impl_glfw.init_for_vulkan(window, true)
	mut init_info := impl_vulkan.InitInfo{}
	// A zero api_version uses the Vulkan backend's header version.
	init_info.instance = app.instance
	init_info.physical_device = app.physical_device
	init_info.device = app.device
	init_info.queue_family = app.queue_family
	init_info.queue = app.queue
	init_info.pipeline_cache = app.pipeline_cache
	init_info.descriptor_pool = app.descriptor_pool
	init_info.min_image_count = app.min_image_count
	init_info.image_count = wd.image_count
	init_info.allocator = app.allocator
	init_info.pipeline_info_main.render_pass = wd.render_pass
	init_info.pipeline_info_main.subpass = 0
	init_info.pipeline_info_main.msaa_samples = vk.SampleCountFlagBits._1
	// A zero sType asks ImGui to use its built-in shaders.
	unsafe {
		init_info.custom_shader_vert_create_info.sType = vk.StructureType(0)
		init_info.custom_shader_frag_create_info.sType = vk.StructureType(0)
	}
	init_info.check_vk_result_fn = check_vk_result
	impl_vulkan.vkinit(&init_info)

	options.initialize(state)

	// No custom fonts are loaded, so Dear ImGui uses its default font.

	// Let CI exercise rendering and orderly cleanup without closing the window manually.
	smoke_frame_limit := C.v_imgui_example_smoke_frame_limit()
	mut rendered_frames := 0

	// Main loop
	for !glfw.window_should_close(window) {
		// Poll and handle events (inputs, window resize, etc.)
		// You can read the io.WantCaptureMouse, io.WantCaptureKeyboard flags to tell if dear imgui wants to use your inputs.
		// - When io.WantCaptureMouse is true, do not dispatch mouse input data to your main application, or clear/overwrite your copy of the mouse data.
		// - When io.WantCaptureKeyboard is true, do not dispatch keyboard input data to your main application, or clear/overwrite your copy of the keyboard data.
		// Generally you may always pass all inputs to dear imgui, and hide them from your application based on those two flags.
		glfw.poll_events()

		// Resize swap chain?
		framebuffer := glfw.framebuffer_size(window)
		fb_width := framebuffer.width
		fb_height := framebuffer.height
		if fb_width > 0 && fb_height > 0
			&& (app.swapchain_rebuild || app.main_window_data.width != fb_width || app.main_window_data.height != fb_height) {
			impl_vulkan.set_min_image_count(app.min_image_count)
			impl_vulkan.create_or_resize_window(app.instance, app.physical_device, app.device, mut wd, app.queue_family, app.allocator, fb_width, fb_height, app.min_image_count)
			app.main_window_data.frame_index = 0
			app.swapchain_rebuild = false
		}
		if glfw.get_window_attrib(window, glfw.iconified) != 0 {
			impl_glfw.sleep(10)
			continue
		}

		// Start the Dear ImGui frame
		impl_vulkan.new_frame()
		impl_glfw.new_frame()
		imgui.new_frame()

		if app.docking_available && app.dockspace_enabled {
			imgui.create_main_dockspace()
		}
		frame(mut app, state)

		// Rendering
		imgui.render()
		draw_data := imgui.get_draw_data()
		is_minimized := C.v_imgui_example_draw_data_is_minimized(draw_data)
		if !is_minimized {
			unsafe {
				wd.clear_value.color.float32[0] = app.clear_color.x * app.clear_color.w
				wd.clear_value.color.float32[1] = app.clear_color.y * app.clear_color.w
				wd.clear_value.color.float32[2] = app.clear_color.z * app.clear_color.w
				wd.clear_value.color.float32[3] = app.clear_color.w
			}
			app.frame_render(mut wd, draw_data)
		}
		imgui.render_platform_viewports()
		if !is_minimized {
			app.frame_present(mut wd)
		}
		rendered_frames++
		if smoke_frame_limit > 0 && rendered_frames >= smoke_frame_limit {
			break
		}
	} // for window_should_close

	// Cleanup
	res = vk.device_wait_idle(app.device)
	assert res == vk.Result.success
	impl_vulkan.shutdown()
	impl_glfw.shutdown()
	options.shutdown(state)
	imgui.destroy_context(ig_ctx)

	app.cleanup_vulkan_window()
	app.cleanup_vulkan()

	glfw.destroy_window(window)
	glfw.terminate()
}

// main

pub struct App {
pub mut:
	allocator             &vk.AllocationCallbacks = unsafe { nil }
	instance              vk.Instance
	physical_device       vk.PhysicalDevice
	device                vk.Device
	queue_family          u32 = max_u32
	queue                 vk.Queue
	pipeline_cache        vk.PipelineCache
	descriptor_pool       vk.DescriptorPool
	main_window_data      impl_vulkan.Window
	min_image_count       u32 = 2
	swapchain_rebuild     bool
	swapchain_image_usage vk.ImageUsageFlags = vk.ImageUsageFlags(vk.ImageUsageFlagBits.color_attachment)
	docking_available     bool
	dockspace_enabled     bool = true
	clear_color           imgui.ImVec4 = imgui.ImVec4{
		x: 0.45
		y: 0.55
		z: 0.60
		w: 1.00
	}
}

@[unsafe]
pub fn glfw_error_callback(error i32, const_description &char) {
	eprintln('GLFW Error ${error}: ${cstring_to_vstring(const_description)}')
}

pub fn check_vk_result(err vk.Result) {
	if err == vk.Result.success {
		return
	}
	eprintln('[vulkan] Error: VkResult = ${err}')
	if int(err) < 0 {
		panic('Critical error!')
	}
}

fn imgui_vulkan_loader(function_name &char, user_data voidptr) voidptr {
	instance := vk.Instance(user_data)
	return voidptr(vk.get_instance_proc_addr(instance, function_name))
}

// Extension names must match completely, including the terminating NUL.
pub fn is_extension_available(properties []vk.ExtensionProperties, extension &char) bool {
	length := unsafe { vstrlen_char(extension) }
	if length >= vk.max_extension_name_size {
		return false
	}
	for p in properties {
		if p.extensionName[length] == 0 && unsafe { vmemcmp(&p.extensionName[0], extension, length) } == 0 {
			return true
		}
	}
	return false
}

pub fn (mut app App) setup_vulkan(mut instance_extensions []&char) {
	mut res := vk.Result.success
	// Create Vulkan Instance
	mut create_info := vk.InstanceCreateInfo{}
	// Enumerate available extensions
	mut ie_properties_count := u32(0)
	mut n := unsafe { nil }
	res = vk.enumerate_instance_extension_properties(unsafe { nil }, &ie_properties_count, mut n)
	check_vk_result(res)
	mut ie_properties := []vk.ExtensionProperties{len: int(ie_properties_count)}
	mut ie_properties_data := ie_properties.data
	res = vk.enumerate_instance_extension_properties(unsafe { nil }, &ie_properties_count, mut ie_properties_data)
	check_vk_result(res)
	// Enable required extensions
	if is_extension_available(ie_properties, vk.khr_get_physical_device_properties_2_extension_name) {
		instance_extensions << vk.khr_get_physical_device_properties_2_extension_name
	}
	if is_extension_available(ie_properties, vk.khr_portability_enumeration_extension_name) {
		instance_extensions << vk.khr_portability_enumeration_extension_name
		create_info.flags |= vk.InstanceCreateFlags(vk.InstanceCreateFlagBits.enumerate_portability)
	}
	// Create Vulkan Instance
	create_info.enabledExtensionCount = u32(instance_extensions.len)
	create_info.ppEnabledExtensionNames = instance_extensions.data
	res = vk.create_instance(&create_info, app.allocator, &app.instance)
	check_vk_result(res)
	vk.load_instance_commands(app.instance)
	// ImGui uses its own no-prototypes dispatch table. Populate it before any
	// impl_vulkan helper; otherwise its first Vulkan call can jump through null.
	if !impl_vulkan.load_functions(vk.api_version_1_0, imgui_vulkan_loader, voidptr(app.instance)) {
		panic('Could not load ImGui Vulkan functions')
	}

	// Select Physical Device (GPU)
	app.physical_device = unsafe { nil }
	app.physical_device = impl_vulkan.select_physical_device(app.instance)
	assert !isnil(app.physical_device)

	// Select graphics queue family
	app.queue_family = impl_vulkan.select_queue_family_index(app.physical_device)
	assert app.queue_family != max_u32

	// Create Logical Device (with 1 queue)
	mut device_extensions := []&char{}
	device_extensions << c'VK_KHR_swapchain'

	// Enumerate physical device extension
	mut de_properties_count := u32(0)
	res = vk.enumerate_device_extension_properties(app.physical_device, unsafe { nil }, &de_properties_count, mut n)
	check_vk_result(res)
	mut de_properties := []vk.ExtensionProperties{len: int(de_properties_count)}
	mut de_properties_data := de_properties.data
	res = vk.enumerate_device_extension_properties(app.physical_device, unsafe { nil }, &de_properties_count, mut de_properties_data)
	check_vk_result(res)

	if is_extension_available(de_properties, c'VK_KHR_portability_subset') {
		device_extensions << c'VK_KHR_portability_subset'
	}

	queue_priority := []f32{len: 1, init: f32(1.0)}
	mut queue_info := []vk.DeviceQueueCreateInfo{len: 1, init: vk.DeviceQueueCreateInfo{}}
	queue_info[0].queueFamilyIndex = app.queue_family
	queue_info[0].queueCount = 1
	queue_info[0].pQueuePriorities = queue_priority.data

	mut device_ci := vk.DeviceCreateInfo{}
	device_ci.queueCreateInfoCount = u32(queue_info.len)
	device_ci.pQueueCreateInfos = queue_info.data
	device_ci.enabledExtensionCount = u32(device_extensions.len)
	device_ci.ppEnabledExtensionNames = device_extensions.data

	res = vk.create_device(app.physical_device, &device_ci, app.allocator, &app.device)
	check_vk_result(res)
	vk.get_device_queue(app.device, app.queue_family, 0, &app.queue)

	// Create Descriptor Pool
	// Dear ImGui 1.92.9+ keeps image views and samplers in separate descriptors.
	// These are the backend's documented minimums for the font atlas; add more
	// sampled-image descriptors for each texture registered by the application.
	mut pool_sizes := []vk.DescriptorPoolSize{}
	pool_sizes << vk.DescriptorPoolSize{
		type: vk.DescriptorType.sampled_image
		descriptorCount: u32(8)
	}
	pool_sizes << vk.DescriptorPoolSize{
		type: vk.DescriptorType.sampler
		descriptorCount: u32(2)
	}
	mut pool_info := vk.DescriptorPoolCreateInfo{}
	pool_info.flags = vk.DescriptorPoolCreateFlags(vk.DescriptorPoolCreateFlagBits.free_descriptor_set)
	pool_info.maxSets = 0
	for pool_size in pool_sizes {
		pool_info.maxSets += pool_size.descriptorCount
	}
	pool_info.poolSizeCount = u32(pool_sizes.len)
	pool_info.pPoolSizes = pool_sizes.data
	res = vk.create_descriptor_pool(app.device, &pool_info, app.allocator, &app.descriptor_pool)
	check_vk_result(res)
}

pub fn (mut app App) setup_vulkan_window(mut wd &impl_vulkan.Window, surface vk.SurfaceKHR, width i32, height i32) {
	wd.surface = surface
	wd.clear_enable = true

	// Check for WSI support
	mut res := vk.Bool32(0)
	vk.get_physical_device_surface_support_khr(app.physical_device, app.queue_family, wd.surface, &res)
	if res != vk._true {
		panic('Error no Window System Integration (WSI) support on physical device 0')
	}

	// Select Surface Format
	request_surface_image_format := [vk.Format.b8g8r8a8_unorm, vk.Format.r8g8b8a8_unorm,
		vk.Format.b8g8r8_unorm, vk.Format.r8g8b8_unorm]
	request_surface_color_space := vk.ColorSpaceKHR.srgb_nonlinear
	wd.surface_format = impl_vulkan.select_surface_format(app.physical_device, wd.surface, &request_surface_image_format[0], i32(request_surface_image_format.len), request_surface_color_space)

	// Select Present Mode
	mut present_modes := []vk.PresentModeKHR{}
	$if app_use_unlimited_frame_rate ? {
		present_modes << vk.PresentModeKHR.mailbox
		present_modes << vk.PresentModeKHR.immediate
		present_modes << vk.PresentModeKHR.fifo
	} $else {
		present_modes << vk.PresentModeKHR.fifo
	}
	wd.present_mode = impl_vulkan.select_present_mode(app.physical_device, wd.surface, present_modes.data, i32(present_modes.len))

	// Create SwapChain, RenderPass, Framebuffer, etc.
	assert app.min_image_count >= 2
	impl_vulkan.create_or_resize_window(app.instance, app.physical_device, app.device, mut wd, app.queue_family, app.allocator, width, height, app.min_image_count)
}

pub fn (mut app App) frame_render(mut wd impl_vulkan.Window, draw_data &imgui.ImDrawData) {
	// Clamp index between 0 and len - 1
	wd.semaphore_index = wd.semaphore_index % u32(wd.frame_semaphores.len)

	image_acquired_semaphore := wd.frame_semaphores[wd.semaphore_index].image_acquired_semaphore
	render_complete_semaphore := wd.frame_semaphores[wd.semaphore_index].render_complete_semaphore
	mut res := vk.acquire_next_image_khr(app.device, wd.swapchain, max_u64, image_acquired_semaphore, unsafe { nil }, &wd.frame_index)
	if res == vk.Result.error_out_of_date_khr || res == vk.Result.suboptimal_khr {
		app.swapchain_rebuild = true
	}
	if res == vk.Result.error_out_of_date_khr {
		return
	}
	if res != vk.Result.suboptimal_khr {
		check_vk_result(res)
	}

	// Wait indefinitely instead of periodically checking
	res = vk.wait_for_fences(app.device, 1, &wd.frames[wd.frame_index].fence, vk._true, max_u64)
	check_vk_result(res)

	res = vk.reset_fences(app.device, 1, &wd.frames[wd.frame_index].fence)
	check_vk_result(res)

	res = vk.reset_command_pool(app.device, wd.frames[wd.frame_index].command_pool, 0)
	check_vk_result(res)

	mut command_buffer_bi := vk.CommandBufferBeginInfo{}
	command_buffer_bi.flags |= vk.CommandBufferUsageFlags(vk.CommandBufferUsageFlagBits.one_time_submit)
	res = vk.begin_command_buffer(wd.frames[wd.frame_index].command_buffer, &command_buffer_bi)
	check_vk_result(res)

	mut render_pass_bi := vk.RenderPassBeginInfo{}
	render_pass_bi.renderPass = wd.render_pass
	render_pass_bi.framebuffer = wd.frames[wd.frame_index].framebuffer
	render_pass_bi.renderArea.extent.width = u32(wd.width)
	render_pass_bi.renderArea.extent.height = u32(wd.height)
	render_pass_bi.clearValueCount = 1
	render_pass_bi.pClearValues = &wd.clear_value
	vk.cmd_begin_render_pass(wd.frames[wd.frame_index].command_buffer, &render_pass_bi, vk.SubpassContents.inline)

	// Record dear imgui primitives into command buffer
	impl_vulkan.render_draw_data(draw_data, wd.frames[wd.frame_index].command_buffer, vk.Pipeline(unsafe { nil }))

	// Submit command buffer
	vk.cmd_end_render_pass(wd.frames[wd.frame_index].command_buffer)

	wait_stage := vk.PipelineStageFlags(vk.PipelineStageFlagBits.color_attachment_output)
	mut submit_i := vk.SubmitInfo{}
	submit_i.waitSemaphoreCount = 1
	submit_i.pWaitSemaphores = &image_acquired_semaphore
	submit_i.pWaitDstStageMask = &wait_stage
	submit_i.commandBufferCount = 1
	submit_i.pCommandBuffers = &wd.frames[wd.frame_index].command_buffer
	submit_i.signalSemaphoreCount = 1
	submit_i.pSignalSemaphores = &render_complete_semaphore

	res = vk.end_command_buffer(wd.frames[wd.frame_index].command_buffer)
	check_vk_result(res)
	res = vk.queue_submit(app.queue, 1, &submit_i, wd.frames[wd.frame_index].fence)
	check_vk_result(res)
}

pub fn (mut app App) frame_present(mut wd impl_vulkan.Window) {
	if app.swapchain_rebuild {
		return
	}
	render_complete_semaphore := wd.frame_semaphores[wd.semaphore_index].render_complete_semaphore
	mut present_i := vk.PresentInfoKHR{}
	present_i.waitSemaphoreCount = 1
	present_i.pWaitSemaphores = &render_complete_semaphore
	present_i.swapchainCount = 1
	present_i.pSwapchains = &wd.swapchain
	present_i.pImageIndices = &wd.frame_index

	res := vk.queue_present_khr(app.queue, &present_i)
	if res == vk.Result.error_out_of_date_khr || res == vk.Result.suboptimal_khr {
		app.swapchain_rebuild = true
	}
	if res == vk.Result.error_out_of_date_khr {
		return
	}
	if res != vk.Result.suboptimal_khr {
		check_vk_result(res)
	}
	// Now we can use the next set of semaphores
	wd.semaphore_index = (wd.semaphore_index + 1) % wd.semaphore_count
}

pub fn (mut app App) cleanup_vulkan_window() {
	impl_vulkan.destroy_window(app.instance, app.device, mut app.main_window_data, app.allocator)
}

pub fn (mut app App) cleanup_vulkan() {
	vk.destroy_descriptor_pool(app.device, app.descriptor_pool, app.allocator)
	vk.destroy_device(app.device, app.allocator)
	vk.destroy_instance(app.instance, app.allocator)
}
