// C++ example at https://github.com/ocornut/imgui/blob/master/examples/example_glfw_vulkan
// Dear ImGui: standalone example application for Glfw + Vulkan

// Learn about Dear ImGui:
// - FAQ                  https://dearimgui.com/faq
// - Getting Started      https://dearimgui.com/getting-started
// - Documentation        https://dearimgui.com/docs (same as your local docs/ folder).
// - Introduction, links and more at the top of imgui.cpp

// Important note to the reader who wish to integrate imgui_impl_vulkan.cpp/.h in their own engine/app.
// - Common ImGui_ImplVulkan_XXX functions and structures are used to interface with imgui_impl_vulkan.cpp/.h.
//   You will use those if you want to use this rendering backend in your engine/app.
// - Helper ImGui_ImplVulkanH_XXX functions and structures are only used by this example (main.cpp) and by
//   the backend itself (imgui_impl_vulkan.cpp), but should PROBABLY NOT be used by your own engine/app code.
// Read comments in imgui_impl_vulkan.h.

module glfw_vulkan


import vulkan as vk
import glfw
import imgui
import imgui.impl_vulkan
import imgui.impl_glfw


pub fn main() {
  glfw.set_error_callback(glfw_error_callback)
  if !glfw.initialize() {
    panic('Could not initialize GLFW')
  }

  // Create window with Vulkan context
  glfw.window_hint(glfw.client_api, glfw.no_api)

  main_scale := f32(1.0)
  window := glfw.create_window(i32(1200 * main_scale), i32(800 * main_scale), 'Dear ImGui V+GLFW+Vulkan example', unsafe{nil}, unsafe{nil})

  if !glfw.vulkan_supported() {
    panic('GLFW: Vulkan Not Supported')
  }

  mut app := App{}
  
  mut extensions := []&char{}
  mut extensions_count := u32(0)
  glfw_extensions := glfw.get_required_instance_extensions(&extensions_count)
  for i in 0..extensions_count {
    unsafe{extensions << glfw_extensions[i]}
  }

  app.setup_vulkan(mut extensions)

  // Create Window Surface
  mut surface := unsafe{nil}
  mut res := glfw.create_window_surface(app.instance, window, app.allocator, &surface)
  assert res == vk.Result.success

  // Create Framebuffers
  mut w := i32(0)
  mut h := i32(0)
  glfw.get_framebuffer_size(window, &w, &h)
  mut wd := &app.main_window_data
  app.setup_vulkan_window(mut wd, surface, w, h)

  // Setup Dear ImGui context
  // IMGUI_CHECKVERSION();
  mut ig_ctx := imgui.create_context(unsafe{nil})
  mut ig_io := imgui.get_io_context_ptr(ig_ctx)
  // Enable Keyboard Controls
  ig_io.ConfigFlags |= u32(imgui.ConfigFlags_.nav_enable_keyboard)
  // Enable Gamepad Controls
  ig_io.ConfigFlags |= u32(imgui.ConfigFlags_.nav_enable_gamepad)
  // Scale fonts by dpi
  ig_io.ConfigFlags |= u32(imgui.ConfigFlags_.dpi_enable_scale_fonts)

  // Setup Dear ImGui style
  imgui.style_colors_dark(unsafe{nil})
  // imgui.style_colors_light(unsafe{nil})
  // imgui.style_colors_classic(unsafe{nil})

  // Setup scaling
  mut style := imgui.get_style()
  // Bake a fixed style scale. (until we have a solution for dynamic style scaling, changing this requires resetting Style + calling this again)
  imgui.style_scale_all_sizes(style, main_scale)

  // Setup Platform/Renderer backends
  impl_glfw.init_for_vulkan(window, true)
  mut init_info := impl_vulkan.InitInfo{}
  // Pass in your value of VkApplicationInfo::apiVersion, otherwise will default to header version.
  // init_info.ApiVersion = vk.api_version_1_4
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
  init_info.render_pass = wd.render_pass
  init_info.subpass = 0
  init_info.msaa_samples = vk.SampleCountFlagBits._1
  init_info.check_vk_result_fn = check_vk_result
  impl_vulkan.vkinit(&init_info)

  // Load Fonts
  // - If no fonts are loaded, dear imgui will use the default font. You can also load multiple fonts and use ImGui::PushFont()/PopFont() to select them.
  // - AddFontFromFileTTF() will return the ImFont* so you can store it if you need to select the font among multiple.
  // - If the file cannot be loaded, the function will return a nullptr. Please handle those errors in your application (e.g. use an assertion, or display an error and quit).
  // - Use '#define IMGUI_ENABLE_FREETYPE' in your imconfig file to use Freetype for higher quality font rendering.
  // - Read 'docs/FONTS.md' for more instructions and details. If you like the default font but want it to scale better, consider using the 'ProggyVector' from the same author!
  // - Remember that in C/C++ if you want to include a backslash \ in a string literal you need to write a double backslash \\ !
  //style.FontSizeBase = 20.0f;
  //io.Fonts->AddFontDefault();
  //io.Fonts->AddFontFromFileTTF("c:\\Windows\\Fonts\\segoeui.ttf");
  //io.Fonts->AddFontFromFileTTF("../../misc/fonts/DroidSans.ttf");
  //io.Fonts->AddFontFromFileTTF("../../misc/fonts/Roboto-Medium.ttf");
  //io.Fonts->AddFontFromFileTTF("../../misc/fonts/Cousine-Regular.ttf");
  //ImFont* font = io.Fonts->AddFontFromFileTTF("c:\\Windows\\Fonts\\ArialUni.ttf");
  //IM_ASSERT(font != nullptr);

  // Our state
  show_demo_window := true
  mut show_another_window := false

  // Main loop
  for !glfw.window_should_close(window) {
    // Poll and handle events (inputs, window resize, etc.)
    // You can read the io.WantCaptureMouse, io.WantCaptureKeyboard flags to tell if dear imgui wants to use your inputs.
    // - When io.WantCaptureMouse is true, do not dispatch mouse input data to your main application, or clear/overwrite your copy of the mouse data.
    // - When io.WantCaptureKeyboard is true, do not dispatch keyboard input data to your main application, or clear/overwrite your copy of the keyboard data.
    // Generally you may always pass all inputs to dear imgui, and hide them from your application based on those two flags.
    glfw.poll_events()

    // Resize swap chain?
    mut fb_width := i32(0)
    mut fb_height := i32(0)
    glfw.get_framebuffer_size(window, &fb_width, &fb_height)
    if fb_width > 0 && fb_height > 0
     && (app.swapchain_rebuild || app.main_window_data.width != fb_width || app.main_window_data.height != fb_height) {
      impl_vulkan.set_min_image_count(app.min_image_count)
      impl_vulkan.create_or_resize_window(app.instance, app.physical_device, app.device, wd, app.queue_family, app.allocator, fb_width, fb_height, app.min_image_count)
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

    // 1. Show the big demo window (Most of the sample code is in ImGui::ShowDemoWindow()! You can browse its code to learn more about Dear ImGui!).
    open := true
    if show_demo_window {
      imgui.show_demo_window(&open)
    }
    // 2. Show a simple window that we create ourselves. We use a Begin/End pair to create a named window.
    // Create a window called "Hello, world!" and append into it.
    _ := imgui.begin(c'Hello, world!', &open, imgui.WindowFlags(0))
    // Display some text (you can use a format strings too)
    imgui.text(c'This is some useful text.')
    // Edit bools storing our window open/close state
    _ := imgui.checkbox(c'Demo Window', &show_demo_window)
    _ := imgui.checkbox(c'Another Window', &show_another_window)

    // Edit 1 float using a slider from 0.0f to 1.0f
    //pub fn slider_float(const_label &char, v &f32, v_min f32, v_max f32, const_format &char, flags SliderFlags) bool
    _ := imgui.slider_float(c'float', &app.f, 0.0, 1.0, unsafe{nil}, imgui.SliderFlags(0))
    //pub fn color_edit3(const_label &char, col &f32, flags ColorEditFlags) bool
    // Edit 3 floats representing a color
    _ := imgui.color_edit3(c'clear color', &f32(&app.clear_color), imgui.ColorEditFlags(0))
    // Buttons return true when clicked (most widgets return true when edited/activated)
    // pub fn button(const_label &char, const_size ImVec2) bool
    button_size := imgui.ImVec2{
      x: 100.0
      y: 30.0
    }
    if imgui.button(c'Button', button_size) {
      app.counter++
    }
    // pub fn same_line(offset_from_start_x f32, spacing f32)
    imgui.same_line(0.0, 0.0)
    counter_txt := 'counter = ${app.counter}'
    imgui.text(counter_txt.str)
    // :6  right-align with six spaces on the left
    // :.1 round to one decimal place
    // :f  do show the 0s at the end, even though they do not change the number
    fps_txt := 'Application average ${(1000 / ig_io.Framerate):.3f} ms/frame (${ig_io.Framerate:6.1} FPS)'
    imgui.text(fps_txt.str)
    imgui.end()

    // 3. Show another simple window.
    if show_another_window {
      // Pass a pointer to our bool variable (the window will have a closing button that will clear the bool when clicked)
      _ := imgui.begin(c'Another Window', &show_another_window, imgui.WindowFlags(0))
      imgui.text(c'Hello from another window!')
      if imgui.button(c'Close Me', button_size) {
        show_another_window = false
      }
      imgui.end()
    }

    // Rendering
    imgui.render()
    draw_data := imgui.get_draw_data()
    is_minimized := draw_data.DisplaySize.x <= 0.0 || draw_data.DisplaySize.y <= 0.0
    if !is_minimized {
      wd.clear_value.color.float32[0] = app.clear_color.x * app.clear_color.w
      wd.clear_value.color.float32[1] = app.clear_color.y * app.clear_color.w
      wd.clear_value.color.float32[2] = app.clear_color.z * app.clear_color.w
      wd.clear_value.color.float32[3] = app.clear_color.w
      app.frame_render(mut wd, draw_data)
      app.frame_present(mut wd)
    }
  } // for window_should_close

  // Cleanup
  res = vk.device_wait_idle(app.device)
  assert res == vk.Result.success
  impl_vulkan.shutdown()
  impl_glfw.shutdown()
  imgui.destroy_context(ig_ctx)

  app.cleanup_vulkan_window()
  app.cleanup_vulkan()

  glfw.destroy_window(window)
  glfw.terminate()
} // main

pub struct App {
pub mut:
  debug_report vk.DebugReportCallbackEXT
  allocator &vk.AllocationCallbacks = unsafe{nil}
  instance vk.Instance
  physical_device vk.PhysicalDevice
  device vk.Device
  queue_family u32 = max_u32
  queue vk.Queue
  pipeline_cache vk.PipelineCache
  descriptor_pool vk.DescriptorPool
  main_window_data impl_vulkan.Window
  min_image_count u32 = 2
  swapchain_rebuild bool
  swapchain_image_usage vk.ImageUsageFlags = vk.ImageUsageFlags(vk.ImageUsageFlagBits.color_attachment)
  f f32
  counter int
  clear_color imgui.ImVec4 = imgui.ImVec4{
    x: 0.45
    y: 0.55
    z: 0.60
    w: 1.00
  }
}

@[unsafe]
pub fn glfw_error_callback(error i32, const_description &char) {
  eprintln("GLFW Error ${error}: ${cstring_to_vstring(const_description)}")
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

@[unsafe]
// pub type PFN_vkDebugReportCallbackEXT = fn (   DebugReportFlagsEXT,   DebugReportObjectTypeEXT,   u64,   usize,   i32,   &char,   &char,   voidptr) 
pub fn debug_report(flags vk.DebugReportFlagsEXT, object_type vk.DebugReportObjectTypeEXT, object u64, location usize, message_code i32, const_p_layer_prefix &char, const_p_message &char, p_user_data voidptr) vk.Bool32 {
  eprintln('[vulkan] Debug report from ObjectType: ${object_type}')
  eprintln('Message: ${cstring_to_vstring(const_p_message)}\n')
  return vk._false
}

pub type String = string
pub fn (s String) equal(arr [vk.max_extension_name_size]char) bool {
  for i, c in s {
    if char(c) != arr[i] {
      return false
    }
  }
  return true
}

pub fn is_extension_available_string(properties []vk.ExtensionProperties, extension string) bool {
  for p in properties {
    if String(extension).equal(p.extensionName) {
      return true
    }
  }
  return false
}

pub fn is_extension_available(properties []vk.ExtensionProperties, extension &char) bool {  for p in properties {
    if unsafe{ vmemcmp(&p.extensionName[0], extension, vstrlen_char(extension)) } == 0 {
      return true
    }
  }
  return false
}


pub fn (mut app App) setup_vulkan(mut instance_extensions []&char) {
  mut res := C.volkInitialize()
  if res != vk.Result.success {
    panic('Could not volkInitialize()')
  }
  // Create Vulkan Instance
  mut create_info := vk.InstanceCreateInfo{}
  // Enumerate available extensions
  mut ie_properties_count := u32(0)
  mut ie_properties := []vk.ExtensionProperties{}
  mut n := unsafe{nil}
  vk.enumerate_instance_extension_properties(unsafe{nil}, &ie_properties_count, mut n)
  check_vk_result(res)
  ie_properties.ensure_cap(int(ie_properties_count))
  mut ie_properties_data := ie_properties.data
  res = vk.enumerate_instance_extension_properties(unsafe{nil}, &ie_properties_count, mut ie_properties_data)
  check_vk_result(res)
  // Enable required extensions
  if is_extension_available(ie_properties, vk.khr_get_physical_device_properties_2_extension_name) {
    instance_extensions << vk.khr_get_physical_device_properties_2_extension_name
  }
  if is_extension_available(ie_properties, vk.khr_portability_enumeration_extension_name) {
    instance_extensions << vk.khr_portability_enumeration_extension_name
    create_info.flags |= vk.InstanceCreateFlags(vk.InstanceCreateFlagBits.enumerate_portability)
  }
  // Enabling validation layers
  mut layers := []&char{len: 1, init: c'VK_LAYER_KHRONOS_validation'}
  create_info.enabledLayerCount = 1
  create_info.ppEnabledLayerNames = layers.data
  instance_extensions << c'VK_EXT_debug_report'
  // Create Vulkan Instance
  create_info.enabledExtensionCount = u32(instance_extensions.len)
  create_info.ppEnabledExtensionNames = instance_extensions.data
  res = vk.create_instance(&create_info, app.allocator, &app.instance)
  check_vk_result(res)
  C.volkLoadInstance(app.instance)

  fn_create_debug_report_callback := vk.PFN_vkCreateDebugReportCallbackEXT(vk.get_instance_proc_addr(app.instance, c'vkCreateDebugReportCallbackEXT'))
  assert !isnil(fn_create_debug_report_callback)
  mut debug_report_ci := vk.DebugReportCallbackCreateInfoEXT{}
  debug_report_ci.flags |= vk.DebugReportFlagsEXT(u32(vk.DebugReportFlagBitsEXT.error) | u32(vk.DebugReportFlagBitsEXT.warning) | u32(vk.DebugReportFlagBitsEXT.performance_warning))
  debug_report_ci.pfnCallback = vk.PFN_vkDebugReportCallbackEXT(debug_report)
  debug_report_ci.pUserData = unsafe{nil}
  res = fn_create_debug_report_callback(app.instance, &debug_report_ci, app.allocator, &app.debug_report)
  check_vk_result(res)

  // Select Physical Device (GPU)
  app.physical_device = unsafe{nil}
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
  mut de_properties := []vk.ExtensionProperties{}
  res = vk.enumerate_device_extension_properties(app.physical_device, unsafe{nil}, &de_properties_count, mut n)
  de_properties.ensure_cap(int(de_properties_count))
  mut de_properties_data := de_properties.data
  res = vk.enumerate_device_extension_properties(app.physical_device, unsafe{nil}, &de_properties_count, mut de_properties_data)
  check_vk_result(res)

  if is_extension_available(de_properties, vk.khr_portability_enumeration_extension_name) {
    device_extensions << vk.khr_portability_enumeration_extension_name
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
  // If you wish to load e.g. additional textures you may need to alter pools sizes and maxSets
  mut pool_sizes := []vk.DescriptorPoolSize{}
  pool_sizes << vk.DescriptorPoolSize{
    type: vk.DescriptorType.combined_image_sampler
    // Current version of the backend use 1 descriptor for the font atlas + as many as additional calls done to ImGui_ImplVulkan_AddTexture().
    // It is expected that as early as Q1 2025 the backend will use a few more descriptors. Use this value + number of desired calls to ImGui_ImplVulkan_AddTexture().
    // #define IMGUI_IMPL_VULKAN_MINIMUM_IMAGE_SAMPLER_POOL_SIZE   (1)     // Minimum per atlas
    descriptorCount: u32(1)
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

  // Check for WSI support
  mut res := vk.Bool32(0)
  vk.get_physical_device_surface_support_khr(app.physical_device, app.queue_family, wd.surface, &res)
  if res != vk._true {
    panic('Error no Window System Integration (WSI) support on physical device 0')
  }
  
  // Select Surface Format
  request_surface_image_format := [vk.Format.b8g8r8a8_unorm, vk.Format.r8g8b8a8_unorm, vk.Format.b8g8r8_unorm, vk.Format.r8g8b8_unorm]
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
  impl_vulkan.create_or_resize_window(app.instance, app.physical_device, app.device, wd, app.queue_family, app.allocator, width, height, app.min_image_count)
}

pub fn (mut app App) frame_render(mut wd impl_vulkan.Window, draw_data &imgui.ImDrawData) {
  // Clamp index between 0 and len - 1
  wd.semaphore_index = wd.semaphore_index % u32(wd.frame_semaphores.len)

  image_acquired_semaphore := wd.frame_semaphores[wd.semaphore_index].image_acquired_semaphore
  render_complete_semaphore := wd.frame_semaphores[wd.semaphore_index].render_complete_semaphore
  mut res := vk.acquire_next_image_khr(app.device, wd.swapchain, max_u64, image_acquired_semaphore, unsafe{nil}, &wd.frame_index)
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
  impl_vulkan.render_draw_data(draw_data, wd.frames[wd.frame_index].command_buffer, vk.Pipeline(unsafe{nil}))

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

  res := vk.queue_present_khr(app.queue,&present_i)
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
  wd.semaphore_index = wd.semaphore_index + 1 % wd.semaphore_count
}

pub fn (mut app App) cleanup_vulkan_window() {
  impl_vulkan.destroy_window(app.instance, app.device, mut app.main_window_data, app.allocator)
}

pub fn (mut app App) cleanup_vulkan() {
  vk.destroy_descriptor_pool(app.device, app.descriptor_pool, app.allocator)

  // Remove debug report callbacl
  f_destroy_debug_report_callback_ext := vk.PFN_vkDestroyDebugReportCallbackEXT(vk.get_instance_proc_addr(app.instance, c'vkDestroyDebugReportCallbackEXT'))
  assert !isnil(f_destroy_debug_report_callback_ext)
  f_destroy_debug_report_callback_ext(app.instance, app.debug_report, app.allocator)

  vk.destroy_device(app.device, app.allocator)
  vk.destroy_instance(app.instance, app.allocator)
}

