
// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// config

ENABLE_VALIDATION_LAYERS :: true;

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// Notes:
// - just using the one queue is probably all I need
// - apparently dynamic rendering is available in < 1.3 as an extension
// - wtf is dynamic rendering?
// - make a deletion queue? (frame-late: simpler. dependencies-met-before deletion version: scary)
// - fifo is just vsync
// - need one VkCommandPool and ! VkCommandBuffer to each thread, and commands can be recorded in parallel
//      all buffers can then be submitted on one thread. (vkQueueSubmit is not thread safe0
//      "big engines" have a thread just for submitting. I suppose that would be easy to do, so why not?


// TODO: custom validation layer callback
// TODO: allocator
// TODO: if graphics and present end up with different queues, validation complains about things I don't understand / haven't looked into
// TODO: I have a VkQueueWaitIdle in the part where we get the next swapchain image. It's there to prevent a situation where the signal semaphore is still signaled...? I suppose meaning that post-present, the semaphore resets. apparently VK_EXT_swapchain_maintenance1 provides a solution for this issue. or, maybe just having one set of sync primitives per image would do it. I'm not really sure. I need to take an hour or two to understand what's going on.
// TODO: to fix the above thing, I can probably just reference the main vulkan tutorial
// TODO: do  I have to recreate the views whe I remake a swapchain?
// TODO: mark the swapchain dirty when its dimensions don't match window dimensions
// TODO: need non-vsync present mode. otherwise, I can't see performance problems coming from afar.

Vulkan :: struct {
    scope_initialize :: () -> bool {
        if init_success then create_vk_instance();
        if init_success then create_surface();
        if init_success then select_physical_device();
        if init_success then create_logical_device();
        if init_success then create_swapchain();
        if init_success then create_image_views();
        // if init_success then create_graphics_pipeline();
        if init_success then init_commands();
        if init_success {
            rm_log("vulkan init success");
        }
        return init_success;
    }
    scope_deinitialize :: () {
        if !init_success then return;
        vkDeviceWaitIdle(logical_device);

        for command_frames {
            vkDestroyCommandPool(logical_device, it.command_pool, null);
            vkDestroyFence(logical_device, it.fence, null);
            vkDestroySemaphore(logical_device, it.render_semaphore, null);
            vkDestroySemaphore(logical_device, it.swapchain_semaphore, null);
        }
        array_reset(*command_frames);

        vkDestroyPipelineLayout(logical_device, test_pipeline_layout, null);
        test_pipeline_layout = null;
        reset(*swapchain);
        vkDestroyDevice(logical_device, null);
        logical_device = null;
        vkDestroySurfaceKHR(vk_instance, surface, null);
        surface = null;
        vkDestroyInstance(vk_instance, null);
        vk_instance = null;
    }
}

should_rebuild_swapchain :: () -> bool {
    window_dimensions := get_window_dimensions();
    if swapchain.extent.width != xx window_dimensions.x || swapchain.extent.height != xx window_dimensions.y {
        return true;
    } else return false;
}

vk_render_frame :: () {
    if quit {
        return;
    }
    if should_rebuild_swapchain() {
        vkQueueWaitIdle(graphics_queue);
        create_swapchain();
        create_image_views();
    }

    current_frame := get_current_frame_data();
    image_index := wait_for_next_swapchain_image(current_frame);
    render_target := swapchain.images[image_index];
    cmd := begin_command_buffer(current_frame);
    transition_image(cmd, render_target, .UNDEFINED, .GENERAL);
    clear_image(cmd, render_target);
    transition_image(cmd, render_target, .GENERAL, .PRESENT_SRC_KHR);
    vk_validate(vkEndCommandBuffer(cmd), "failed to end the main command buffer");

    submit_command_info := command_buffer_submit_info(cmd);
    wait_info := semaphore_submit_info(VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT_KHR, current_frame.swapchain_semaphore);
    signal_info := semaphore_submit_info(VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT, current_frame.render_semaphore);
    submit_info := roll_submit_info(*submit_command_info, *signal_info, *wait_info);

    // smoke
    vk_validate(vkQueueSubmit2(graphics_queue, 1, *submit_info, null), "failed to submit draw commands to the graphics queue");

    present_info := VkPresentInfoKHR.{
        pSwapchains = *swapchain.vk_obj,
        swapchainCount = 1,
        pWaitSemaphores = *current_frame.render_semaphore,
        waitSemaphoreCount = 1,
        pImageIndices = *image_index,
    };
    present_fence_info := VkSwapchainPresentFenceInfoEXT.{
        swapchainCount = 1,
        pFences=*current_frame.fence,
    };
    present_info.pNext = *present_fence_info;

    vk_validate(vkQueuePresentKHR(graphics_queue, *present_info), "failed to present the render target");
    frame += 1;
}


#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// tick:15

transition_image :: (cmd: VkCommandBuffer, image: VkImage, old_layout: VkImageLayout, new_layout: VkImageLayout) {
    image_barrier := VkImageMemoryBarrier2.{
        srcStageMask = VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
        srcAccessMask = VK_ACCESS_2_MEMORY_WRITE_BIT,
        dstStageMask = VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
        dstAccessMask = VK_ACCESS_2_MEMORY_WRITE_BIT | VK_ACCESS_2_MEMORY_READ_BIT,
        oldLayout = old_layout,
        newLayout = new_layout,
        subresourceRange = .{
            aspectMask = ifx new_layout == .DEPTH_ATTACHMENT_OPTIMAL then .DEPTH_BIT else .COLOR_BIT, 
            baseMipLevel = 0,
            levelCount = VK_REMAINING_MIP_LEVELS,
            baseArrayLayer = 0,
            layerCount = VK_REMAINING_ARRAY_LAYERS
        },
        image = image
    };

    dependency_info := VkDependencyInfo.{
        imageMemoryBarrierCount = 1,
        pImageMemoryBarriers = *image_barrier
    };

    vkCmdPipelineBarrier2(cmd, *dependency_info);
}

semaphore_submit_info :: inline (stage_mask: VkPipelineStageFlags2, semaphore: VkSemaphore) -> VkSemaphoreSubmitInfo {
    return .{
        semaphore = semaphore,
        stageMask = stage_mask,
        // deviceIndex = 0,
        value = 1
    };
}

command_buffer_submit_info :: inline (cmd: VkCommandBuffer) -> VkCommandBufferSubmitInfo {
    return .{
        commandBuffer = cmd,
        // deviceMask = 0
    };
}

roll_submit_info :: inline (cmd: *VkCommandBufferSubmitInfo, signal_semaphore_info: *VkSemaphoreSubmitInfo, wait_semaphore_info: *VkSemaphoreSubmitInfo) -> VkSubmitInfo2 {
    return .{
        waitSemaphoreInfoCount = ifx wait_semaphore_info == null then (0).(u32) else (1).(u32),
        pWaitSemaphoreInfos = wait_semaphore_info,
        signalSemaphoreInfoCount = ifx signal_semaphore_info == null then (0).(u32) else (1).(u32),
        pSignalSemaphoreInfos = signal_semaphore_info,
        commandBufferInfoCount = 1,
        pCommandBufferInfos = cmd
    };
}

clear_image :: (cmd: VkCommandBuffer, target: VkImage) {
    // blue := respace(sin(seconds_since_init() / 2.0).(float32), .{-1, 1}, .{0, 1});
    // red := 1.0 - blue;
    // green := red * 0.5;
    // clear_value := VkClearColorValue.{
    //     _float32 = .[red, green, blue, 1]
    // };
    clear_value := VkClearColorValue.{
        _float32 = .[0, 0, 1, 1]
    };
    clear_range := VkImageSubresourceRange.{
        aspectMask = .COLOR_BIT, 
        baseMipLevel = 0,
        levelCount = VK_REMAINING_MIP_LEVELS,
        baseArrayLayer = 0,
        layerCount = VK_REMAINING_ARRAY_LAYERS
    };
    vkCmdClearColorImage(cmd, target, .GENERAL, *clear_value, 1, *clear_range);
}

begin_command_buffer :: (frame: *Frame_Data) -> VkCommandBuffer {
    cmd := frame.command_buffer;
    vk_validate(vkResetCommandBuffer(cmd, 0), "failed to reset the main command buffer");
    command_buffer_begin := VkCommandBufferBeginInfo.{
        flags = .ONE_TIME_SUBMIT_BIT
    };
    vk_validate(vkBeginCommandBuffer(cmd, *command_buffer_begin), "failed to begin the main command buffer");
    return cmd;
}

wait_for_next_swapchain_image :: (current_frame: *Frame_Data) -> u32 {
    vk_validate(vkWaitForFences(logical_device, 1, *current_frame.fence, VK_TRUE, ONE_SECOND_IN_NANOSECONDS), "failed to wait for the render fence");
    vk_validate(vkResetFences(logical_device, 1, *current_frame.fence), "failed to reset the render fence");
    image_index: u32;
    vk_validate(vkAcquireNextImageKHR(logical_device, swapchain.vk_obj, ONE_SECOND_IN_NANOSECONDS, current_frame.swapchain_semaphore, null, *image_index), "failed to wait to get an image from the swapchain");
    return image_index;
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// initialize

create_vk_instance :: () {
    auto_release_temp();

    vk_init_validate(instance_extensions_are_supported(required_instance_extensions), "required instance extensions unsupported");

    no_validation := !ENABLE_VALIDATION_LAYERS;
    layers_supported := layers_are_supported(required_layers);
    vk_init_validate(no_validation || layers_supported, "the required validation layers are not supported");

    app_info := VkApplicationInfo .{
        pApplicationName = "ImSimGame",
        applicationVersion = VK_MAKE_VERSION(0,1,0),
        pEngineName = "Red_Mango",
        engineVersion = VK_MAKE_VERSION(0,1,0),
        apiVersion = VK_API_VERSION_1_3
    };
    create_info := VkInstanceCreateInfo.{
        pApplicationInfo = *app_info,
        enabledLayerCount = xx required_layers.count,
        ppEnabledLayerNames = required_layers.data,
        enabledExtensionCount = xx required_instance_extensions.count,
        ppEnabledExtensionNames = required_instance_extensions.data
    };
    vk_init_validate(vkCreateInstance(*create_info, null, *vk_instance), "failed to create vulkan instance");
}

create_surface :: () {
    create_info := VkWin32SurfaceCreateInfoKHR.{
        hwnd = window,
        hinstance = GetModuleHandleW(null)
    };
    vk_init_validate(vkCreateWin32SurfaceKHR(vk_instance, *create_info, null, *surface), "failed to create surface");
}

select_physical_device :: () {
    auto_release_temp();

    physical_device = .{};

    success, physical_devices := get_physical_devices();
    vk_init_validate(success, "unable to enumerate physical devices");
    vk_init_validate(physical_devices.count > 0, "no available physical devices on the system");

    best_score: s32;
    best_scored_device: VkPhysicalDevice;

    for physical_devices {
        device_score := score_physical_device(it);
        if device_score > best_score {
            best_score = device_score;
            best_scored_device = it;
        }
    }

    vk_init_validate(best_scored_device != null, "unable to find a suitable physical device");

    physical_device.vk_obj = best_scored_device;
    success = set_physical_device_queue_family_capabilities(*physical_device);
    vk_init_validate(success, "unable to set selected physical device queue family properties");
}

create_logical_device :: () {
    auto_release_temp();

    queue_priority : float32 = 1.0;
    unique_queue_family_indices := get_unique_queue_family_indices();
    queue_create_infos_backdata: [4]VkDeviceQueueCreateInfo;
    queue_create_infos := bound_array(queue_create_infos_backdata);

    for unique_queue_family_indices {
        queue_create_info := VkDeviceQueueCreateInfo.{
            queueFamilyIndex = it,
            queueCount = 1,
            pQueuePriorities = *queue_priority,
        };
        bound_array_add(*queue_create_infos, queue_create_info);
    }

    enable_device_features: VkPhysicalDeviceFeatures;

    maintenance1_enable := VkPhysicalDeviceSwapchainMaintenance1FeaturesEXT.{
        swapchainMaintenance1 = VK_TRUE
    };
    sync_feature_enable := VkPhysicalDeviceSynchronization2Features.{
        synchronization2 = VK_TRUE,
        pNext = *maintenance1_enable
    };

    device_create_info := VkDeviceCreateInfo.{
        pQueueCreateInfos = queue_create_infos.array.data,
        queueCreateInfoCount = xx queue_create_infos.array.count,
        pEnabledFeatures = *enable_device_features,
        enabledLayerCount = xx required_layers.count,
        ppEnabledLayerNames = xx required_layers.data,
        enabledExtensionCount = xx required_device_extensions.count,
        ppEnabledExtensionNames = required_device_extensions.data,
        pNext = *sync_feature_enable
    };

    result := vkCreateDevice(physical_device.vk_obj, *device_create_info, null, *logical_device);
    vk_init_validate(result, "failed to create the logical device");

    vkGetDeviceQueue(logical_device, xx physical_device.graphics_index, 0, *graphics_queue);
}

create_swapchain :: () {
    auto_release_temp();

    old_swapchain := swapchain.vk_obj;
    reset(*swapchain, false);

    support_info: Swapchain_Support_Info;
    vk_init_validate(get_swapchain_support_info(physical_device.vk_obj, *support_info, temp), "unable to get swapchain support info for the selected physical device");
    vk_init_validate(support_info.present_modes.count > 0 && support_info.formats.count > 0, "insufficient number or present modes or surface formats to create a swap chain");

    swapchain.format = choose_swapchain_surface_format(*support_info);
    swapchain.present_mode = choose_swapchain_present_mode(*support_info);
    swapchain.extent = choose_swapchain_extent(*support_info);

    max_image_count : u32 = ifx support_info.capabilities.maxImageCount == 0 then U32_MAX else support_info.capabilities.maxImageCount;
    image_count := min(support_info.capabilities.minImageCount + 1, max_image_count);

    create_info := VkSwapchainCreateInfoKHR.{
        surface = surface,
        minImageCount = image_count,
        imageFormat = swapchain.format.format,
        imageColorSpace = swapchain.format.colorSpace,
        imageExtent = swapchain.extent,
        // layers per image
        imageArrayLayers = 1,
        // render directly to the image
        imageUsage = .COLOR_ATTACHMENT_BIT | .TRANSFER_DST_BIT,
        // how to transform the image before... presenting?
        preTransform = support_info.capabilities.currentTransform,
        // whether the alpha channel should blend with other windows
        compositeAlpha = .OPAQUE_BIT_KHR,
        presentMode = swapchain.present_mode,
        clipped = VK_TRUE,
        oldSwapchain = old_swapchain
    };

    assert(physical_device.graphics_index >= 0 && physical_device.present_index >= 0);
    queue_family_indices := u32.[xx physical_device.graphics_index, xx physical_device.present_index];
    if physical_device.graphics_index != physical_device.present_index {
        create_info.imageSharingMode = .CONCURRENT;
        create_info.queueFamilyIndexCount = xx queue_family_indices.count;
        create_info.pQueueFamilyIndices = queue_family_indices.data;
    } else {
        // best perf according to somebody. only one queue family owns an image at a time.
        create_info.imageSharingMode = .EXCLUSIVE; 
    }

    vk_init_validate(vkCreateSwapchainKHR(logical_device, *create_info, null, *swapchain.vk_obj), "failed creating the swapchain");

    success:, swapchain.images = get_swapchain_images(context.allocator);
    vk_init_validate(success, "unable to get the array of swapchain images");

    if old_swapchain {
        vkDestroySwapchainKHR(logical_device, old_swapchain, null);
    }
}

create_image_views :: () {
    auto_release_temp();

    swapchain.image_views = alloc_array(VkImageView, swapchain.images.count);
    for swapchain.images {
        create_info := VkImageViewCreateInfo.{
            image = it,
            viewType = ._2D,
            format = swapchain.format.format,
            // image's purpose and which part of the image should be accessed. it's a color target without mips or extra layers
            subresourceRange = .{
                aspectMask = .COLOR_BIT,
                baseMipLevel = 0,
                levelCount = 1,
                baseArrayLayer = 0,
                layerCount = 1
            }
        };
        vk_init_validate(vkCreateImageView(logical_device, *create_info, null, *swapchain.image_views[it_index]), "unable to create an image view for a swapchain image");
    }
}

create_graphics_pipeline :: () {
    auto_release_temp();

    test_frag := create_shader_module_from_file("shaders/frag.spv");
    vk_init_validate(test_frag != null, "failed to create fragment shader module");
    defer vkDestroyShaderModule(logical_device, test_frag, null);
    test_vert := create_shader_module_from_file("shaders/vert.spv");
    vk_init_validate(test_vert != null, "failed to create vertex shader module");
    defer vkDestroyShaderModule(logical_device, test_vert, null);

    shader_stages := VkPipelineShaderStageCreateInfo.[
     .{
        stage = .VERTEX_BIT,
        module = test_vert,
        pName = "main"
    }, 
    .{
        stage = .FRAGMENT_BIT,
        module = test_frag,
        pName = "main"
    }];

    vertex_input_info := VkPipelineVertexInputStateCreateInfo.{
        vertexBindingDescriptionCount = 0,
        pVertexBindingDescriptions = null,
        vertexAttributeDescriptionCount = 0,
        pVertexAttributeDescriptions = null
    };

    input_assemby_info := VkPipelineInputAssemblyStateCreateInfo.{
        topology = .TRIANGLE_LIST,
    };

    viewport := VkViewport.{
        width = xx swapchain.extent.width,
        height = xx swapchain.extent.height,
        minDepth = 0.0,
        maxDepth = 1.0
    };

    scissor := VkRect2D.{
        extent = swapchain.extent
    };

    dynamic_states := VkDynamicState.[
        .VIEWPORT,
        .SCISSOR
    ];

    dynamic_state := VkPipelineDynamicStateCreateInfo.{
        dynamicStateCount = xx dynamic_states.count,
        pDynamicStates = dynamic_states.data
    };

    viewport_create_info := VkPipelineViewportStateCreateInfo.{
        viewportCount = 1,
        scissorCount = 1
    };

    rasterizer_create_info := VkPipelineRasterizationStateCreateInfo.{
        depthClampEnable = VK_FALSE,
        rasterizerDiscardEnable = VK_FALSE,
        polygonMode = .FILL,
        lineWidth = 1.0,
        cullMode = .BACK_BIT,
        frontFace = .CLOCKWISE,
        depthBiasEnable = VK_FALSE,
        depthBiasConstantFactor = 0.0,
        depthBiasClamp = 0.0,
        depthBiasSlopeFactor = 0.0
    };

    multisample_create_info := VkPipelineMultisampleStateCreateInfo.{
        sampleShadingEnable = VK_FALSE,
        rasterizationSamples = ._1_BIT,
        minSampleShading = 1.0,
        pSampleMask = null,
        alphaToCoverageEnable = VK_FALSE,
        alphaToOneEnable = VK_FALSE
    };

    color_blend_attachment := VkPipelineColorBlendAttachmentState.{
        colorWriteMask = .R_BIT | .G_BIT | .B_BIT | .A_BIT,
        blendEnable = VK_FALSE,
        srcColorBlendFactor = .SRC_ALPHA,
        dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
        colorBlendOp = .ADD,
        srcAlphaBlendFactor = .ONE,
        dstAlphaBlendFactor = .ZERO,
        alphaBlendOp = .ADD
    };

    color_blend_create := VkPipelineColorBlendStateCreateInfo.{
        logicOpEnable = VK_FALSE,
        logicOp = .COPY,
        attachmentCount = 1,
        pAttachments = *color_blend_attachment
    };

    pipeline_layout_info := VkPipelineLayoutCreateInfo.{
        setLayoutCount = 0,
        pSetLayouts = null,
        pushConstantRangeCount = 0,
        pPushConstantRanges = null
    };

    vk_init_validate(vkCreatePipelineLayout(logical_device, *pipeline_layout_info, null, *test_pipeline_layout), "failed to create the graphics pipeline layout");

}

init_commands :: () {
    auto_release_temp();

    assert(command_frames.data == null);
    command_frames = alloc_array(Frame_Data, swapchain.images.count);

    command_pool_info := VkCommandPoolCreateInfo.{
        flags = .RESET_COMMAND_BUFFER_BIT,
        queueFamilyIndex = xx physical_device.graphics_index
    };

    fence_info := VkFenceCreateInfo.{
        flags = .SIGNALED_BIT
    };
    semaphore_info := VkSemaphoreCreateInfo.{};

    for 0..command_frames.count-1 {
        vk_init_validate(vkCreateCommandPool(logical_device, *command_pool_info, null, *command_frames[it].command_pool), "failed to create a command pool");
        command_alloc_info := VkCommandBufferAllocateInfo.{
            commandPool = command_frames[it].command_pool,
            commandBufferCount = 1,
            level = .PRIMARY
        };
        vk_init_validate(vkAllocateCommandBuffers(logical_device, *command_alloc_info, *command_frames[it].command_buffer), "failed to create a command buffer");
        vk_init_validate(vkCreateFence(logical_device, *fence_info, null, *command_frames[it].fence), "failed to create a render fence");
        vk_init_validate(vkCreateSemaphore(logical_device, *semaphore_info, null, *command_frames[it].render_semaphore), "failed to create a semaphore for syncing render to present");
        vk_init_validate(vkCreateSemaphore(logical_device, *semaphore_info, null, *command_frames[it].swapchain_semaphore), "failed to create a semaphore for syncing render commands to a swapchain image request");
    }

}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// runtime

create_shader_module_from_file :: (filename: string) -> VkShaderModule {
    auto_release_temp();
    file_data: string;
    {
        scope_set_allocator(temp);
        file_data = read_entire_file(filename, true);
    }
    return create_shader_module(file_data);
}

create_shader_module :: (spirv: string) -> VkShaderModule {
    create_info := VkShaderModuleCreateInfo.{
        codeSize = xx spirv.count,
        pCode = xx spirv.data
    };
    module: VkShaderModule;
    if !vk_validate(vkCreateShaderModule(logical_device, *create_info, null, *module), "failed to create a shader module from (assumed) spirv data") {
        return null;
    }
    return module;
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// init helpers

// TODO: < 0 error values are total failure, > 0 mean something else. account for this.

vk_init_validate :: (result: $T, error_msg: string, msg_args: ..Any, caller_loc := #caller_location) -> bool #expand 
#modify { return T == bool || T == VkResult; } {
    error_code_str: string;
    #if T == VkResult {
        failure := result != .SUCCESS;
        error_code_str = tprint("[VK ERROR: %] ", result);
    } else {
        failure := !result;
    }
    if failure {
        rm_error(tprint("vulkan init %:: %", error_code_str, error_msg), ..msg_args, true, caller_loc);
        init_success = false;
        `return;
    }
}

Vk_Validate_Severity :: enum {
    WARNING_MESSAGE;
    ERROR_MESSAGE;
    ASSERT;
}

vk_validate :: (result: $T, error_msg: string, severity := Vk_Validate_Severity.ASSERT, msg_args: ..Any, caller_loc := #caller_location) -> bool #expand 
#modify { return T == bool || T == VkResult; } {
    error_code_str: string;
    #if T == VkResult {
        failure := result != .SUCCESS;
        error_code_str = tprint("[VK ERROR: %] ", result);
    } else {
        failure := !result;
    }
    if failure {
        if severity == .WARNING_MESSAGE {
            rm_warning(tprint("vulkan %:: %", error_code_str, error_msg), ..msg_args, true, caller_loc);
        } else {
            rm_error(tprint("vulkan %:: %", error_code_str, error_msg), ..msg_args, true, caller_loc);
            if severity == .ASSERT {
                assert(false);
            }
        }
        return false;
    }
    return true;
}

to_string :: (data: []u8) -> string {
    return string.{c_style_strlen(data.data), data.data};
}

layers_are_supported :: (layers: []*u8) -> bool {
    auto_release_temp();
    
    success, available_layers := get_available_layer_properties();
    if !success then return false;

    for need_layer : layers {
        layer_found: bool;
        for have_layer : available_layers {
            max_read_ct := have_layer.layerName.count;
            if c_strings_equal(need_layer, have_layer.layerName.data, max_read_ct) {
                layer_found = true;
                break;
            }
        }
        if !layer_found {
            rm_warning("unable to find layer % in available layers", to_string(need_layer));
            return false;
        }
    }

    return true;
}

get_unique_queue_family_indices :: () -> []u32 {
    already_made_queue: Queue_Family_Capability_Flags;
    queue_family_indices := queue_family_index_array(*physical_device);
    unique_indices_buffer := alloc_array(u32, 4, temp);
    unique_indices := bound_array(unique_indices_buffer);
    for 0..3 {
        flag := (1 << queue_family_indices[it]).(Queue_Family_Capability_Flags);
        if (already_made_queue & flag) != 0 {
            continue;
        }
        bound_array_add(*unique_indices, xx it);
        already_made_queue |= flag;
    }
    return unique_indices.array;
}

instance_extensions_are_supported :: (extensions: []*u8) -> bool {
    auto_release_temp();

    success, available_extensions := get_instance_extension_properties();
    if !success then return false;

    for need_ext : extensions {
        ext_found: bool;
        for have_ext : available_extensions {
            max_read_ct := have_ext.extensionName.count;
            if c_strings_equal(need_ext, have_ext.extensionName.data, max_read_ct) {
                ext_found = true;
                break;
            }
        }
        if !ext_found {
            return false;
        }
    }

    return true;
}

device_extensions_are_supported :: (device: VkPhysicalDevice, extensions: []*u8) -> bool {
    auto_release_temp();

    success, available_extensions := get_device_extension_properties(device);
    if !success then return false;

    for need_ext : extensions {
        ext_found: bool;
        for have_ext : available_extensions {
            max_read_ct := have_ext.extensionName.count;
            if c_strings_equal(need_ext, have_ext.extensionName.data, max_read_ct) {
                ext_found = true;
                break;
            }
        }
        if !ext_found {
            return false;
        }
    }

    return true;
}

list_instance_extensions :: () {
    success, available_extensions := get_instance_extension_properties();
    if !success {
        rm_log("no extensions found");
    }
    for have_ext : available_extensions {
        rm_log("have instance extension: %", as_string(have_ext.extensionName));
    }
}

list_device_extensions :: (device: VkPhysicalDevice) {
    success, available_extensions := get_device_extension_properties(device);
    if !success {
        rm_log("no extensions found");
    }
    for have_ext : available_extensions {
        rm_log("have device extension: %", as_string(have_ext.extensionName));
    }
}

score_physical_device :: (device: VkPhysicalDevice) -> score: s32 {
    properties: VkPhysicalDeviceProperties;
    features: VkPhysicalDeviceFeatures;
    vkGetPhysicalDeviceProperties(device, *properties);
    vkGetPhysicalDeviceFeatures(device, *features);

    if !features.geometryShader {
        return 0;
    }
    dummy_device := Physical_Device.{vk_obj=device};
    if !set_physical_device_queue_family_capabilities(*dummy_device) {
        return 0;
    }
    if dummy_device.graphics_index == -1 || dummy_device.present_index == -1 {
        return 0;
    }
    if !device_extensions_are_supported(device, required_device_extensions) {
        return 0;
    }
    info: Swapchain_Support_Info;
    if !get_swapchain_support_info(device, *info, temp) {
        return 0;
    }
    if info.present_modes.count == 0 || info.formats.count == 0 {
        return 0;
    }


    score : s32 = ifx properties.deviceType == .DISCRETE_GPU then (100).(s32) else (1).(s32);
    score += properties.limits.maxImageDimension2D.(s32);
    if dummy_device.graphics_index == dummy_device.present_index then score += 25;
    return score;
}

get_swapchain_support_info :: (device: VkPhysicalDevice, info: *Swapchain_Support_Info, allocator: Allocator) -> bool {
    if !vk_validate(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, *info.capabilities), "unable to get surface capabilities of a physical device", .WARNING_MESSAGE) {
        return false;
    }
    {
        success:, info.formats = get_physical_device_surface_formats(device, surface, allocator);
        if !success || info.formats.count == 0 {
            return false;
        }
    }
    {
        success:, info.present_modes = get_physical_device_surface_present_modes(device, surface, allocator);
        if !success || info.present_modes.count == 0 {
            return false;
        }
    }
    return true;
}

set_physical_device_queue_family_capabilities :: (device: *Physical_Device) -> bool {
    device.queue_family_indices = .{};

    success, queue_family_properties := get_physical_device_queue_family_properties(device.vk_obj);
    if !success then return false;

    GRAPHICS_AND_COMPUTE : VkQueueFlagBits : (.GRAPHICS_BIT | .COMPUTE_BIT);

    for family : queue_family_properties {
        present_support: VkBool32;
        vkGetPhysicalDeviceSurfaceSupportKHR(device.vk_obj, xx it_index, surface, *present_support);
        // just try to get them all on the same queue for now. maybe forever?
        if present_support {
            if (family.queueFlags & GRAPHICS_AND_COMPUTE) == GRAPHICS_AND_COMPUTE {
                device.present_index = xx it_index;
                device.graphics_index = xx it_index;
                device.compute_index = xx it_index;
            } else if device.present_index == -1 {
                device.present_index = xx it_index;
            } 
        }
        if family.queueFlags & .GRAPHICS_BIT && device.graphics_index == -1 {
            device.graphics_index = xx it_index;
        }
        if family.queueFlags & .COMPUTE_BIT && device.compute_index == -1 {
            device.compute_index = xx it_index;
        }
        if family.queueFlags & .TRANSFER_BIT {
            if device.transfer_index == -1 || family.queueFlags & (.GRAPHICS_BIT | .COMPUTE_BIT) == 0 {
                device.transfer_index = xx it_index;
            }
        }
    }
    return true;
}

queue_family_index_array :: inline (physical_device: *Physical_Device) -> []s32 {
    arr: []s32 = ---;
    arr.count = 4;
    arr.data = *physical_device.present_index;
    return arr;
}

choose_swapchain_surface_format :: (info: *Swapchain_Support_Info) -> VkSurfaceFormatKHR {
    for info.formats {
        if it.format == .R8G8B8A8_SRGB && it.colorSpace == .COLOR_SPACE_SRGB_NONLINEAR_KHR {
            return it;
        }
    }
    return info.formats[0];
}

choose_swapchain_present_mode :: (info: *Swapchain_Support_Info) -> VkPresentModeKHR {
    return .FIFO_KHR;
}

choose_swapchain_extent :: (using info: *Swapchain_Support_Info) -> VkExtent2D {
    window_dimensions := get_window_dimensions();
    extent := VkExtent2D.{
        clamp(window_dimensions.x.(u32), capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
        clamp(window_dimensions.y.(u32), capabilities.minImageExtent.height, capabilities.maxImageExtent.height),
    };
    return extent;
}

// there are lots of tedious repetitions of the same process where you want an array of data from vulkan,
// but first you need to know how big the array will be, then you need to check if getting the count
// was successful, then you can alloc and get the array and finally you need to check if doing that 
// was successful. this makes it easy to generate a function that does all of that. I can't say it saves a 
// ton of time, but I think it makes the resulting code easier to read.
generate_vk_array_getter :: (gen_proc_name: string, gen_proc_args: string, vk_proc_name: string, out_array_type_name: string, vk_proc_args: []string, check_success: bool) -> string {
    first_call_args := duplicate(vk_proc_args, temp);
    second_call_args := vk_proc_args;

    first_call_builder: String_Builder;
    first_call_builder.allocator = temp;
    second_call_builder: String_Builder;
    second_call_builder.allocator = temp;
    for 0..first_call_args.count-1 {
        if first_call_args[it] == "out_array.data" {
            first_call_args[it] = "null";
        }
        if it != first_call_args.count-1 {
            print_to_builder(*first_call_builder, "%,", first_call_args[it]);
            print_to_builder(*second_call_builder, "%,", second_call_args[it]);
        } else {
            print_to_builder(*first_call_builder, "%", first_call_args[it]);
            print_to_builder(*second_call_builder, "%", second_call_args[it]);
        }
    }
    first_call_arg_str := builder_to_string(*first_call_builder);
    second_call_arg_str := builder_to_string(*second_call_builder);

    check_success_str_1 := ifx check_success then "|| result != .SUCCESS" else "";
    check_success_str_2 := ifx check_success then "result == .SUCCESS" else "true";
    allocator_param := ifx gen_proc_args.count > 0 then ", allocator := temp" else "allocator := temp";

    return tprint(
#string HERE
% :: (%0%) -> bool, []% {
    out_count: u32;
    result := %(%);
    if out_count == 0 % then return false, .[];
    out_array := alloc_array(%, xx out_count, allocator);
    result = %(%);
    return %, out_array;
}
HERE,
        gen_proc_name, gen_proc_args, allocator_param, out_array_type_name, vk_proc_name, first_call_arg_str, check_success_str_1, out_array_type_name, vk_proc_name, second_call_arg_str, check_success_str_2
    );
}

#insert #run generate_vk_array_getter(
    "get_available_layer_properties", 
    "",  
    "vkEnumerateInstanceLayerProperties", 
    "VkLayerProperties",
    .["*out_count", "out_array.data"],
    true
);
#insert #run generate_vk_array_getter(
    "get_physical_devices", 
    "", 
    "vkEnumeratePhysicalDevices", 
    "VkPhysicalDevice", 
    .["vk_instance", "*out_count", "out_array.data"],
    true
);
#insert #run generate_vk_array_getter(
    "get_device_extension_properties", 
    "device: VkPhysicalDevice",
    "vkEnumerateDeviceExtensionProperties", 
    "VkExtensionProperties", 
    .["device", "null", "*out_count", "out_array.data"],
    true
);
#insert #run generate_vk_array_getter(
    "get_instance_extension_properties",
    "",
    "vkEnumerateInstanceExtensionProperties",
    "VkExtensionProperties",
    .["null", "*out_count", "out_array.data"],
    true
);
#insert #run generate_vk_array_getter(
    "get_physical_device_queue_family_properties",
    "device: VkPhysicalDevice",
    "vkGetPhysicalDeviceQueueFamilyProperties",
    "VkQueueFamilyProperties",
    .["device", "*out_count", "out_array.data"],
    false
);
#insert #run generate_vk_array_getter(
    "get_physical_device_surface_formats",
    "device: VkPhysicalDevice, surface: VkSurfaceKHR",
    "vkGetPhysicalDeviceSurfaceFormatsKHR",
    "VkSurfaceFormatKHR",
    .["device", "surface", "*out_count", "out_array.data"],
    true
);
#insert #run generate_vk_array_getter(
    "get_physical_device_surface_present_modes",
    "device: VkPhysicalDevice, surface: VkSurfaceKHR",
    "vkGetPhysicalDeviceSurfacePresentModesKHR",
    "VkPresentModeKHR",
    .["device", "surface", "*out_count", "out_array.data"],
    true
);
#insert #run generate_vk_array_getter(
    "get_swapchain_images",
    "",
    "vkGetSwapchainImagesKHR",
    "VkImage",
    .["logical_device", "swapchain.vk_obj", "*out_count", "out_array.data"],
    true
);

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// types

Queue_Family_Capability_Flags :: enum_flags {
    PRESENT;
    GRAPHICS;
    COMPUTE;
    TRANSFER;
}

Queue_Family_Indices :: struct {
    present_index: s32 = -1;
    graphics_index: s32 = -1;
    compute_index: s32 = -1;
    transfer_index: s32 = -1;
}

Physical_Device :: struct {
    vk_obj: VkPhysicalDevice;
    type: VkPhysicalDeviceType;
    size: VkDeviceSize;
    using queue_family_indices: Queue_Family_Indices;
}

Swapchain_Support_Info :: struct {
    capabilities: VkSurfaceCapabilitiesKHR;
    formats: []VkSurfaceFormatKHR;
    present_modes: []VkPresentModeKHR;
}

Swapchain :: struct {
    vk_obj: VkSwapchainKHR;
    extent: VkExtent2D;
    format: VkSurfaceFormatKHR;
    present_mode: VkPresentModeKHR;
    // the underlying image datas. not explicitly created by the vulkan api user, so not destroyed by vulkan api user.
    images: []VkImage;
    // the interface for an image. how to access it. texture and possibly a render target. in this case, definitely a render target.
    image_views: []VkImageView;
}

reset :: (swapchain: *Swapchain, destroy_vk_obj := true) {
    if destroy_vk_obj {
        vkDestroySwapchainKHR(logical_device, swapchain.vk_obj, null);
    }
    for swapchain.image_views {
        vkDestroyImageView(logical_device, it, null);
    }
    array_reset(*swapchain.images);
    array_reset(*swapchain.image_views);
    swapchain.* = .{};
}

Frame_Data :: struct {
    command_pool: VkCommandPool;
    command_buffer: VkCommandBuffer;
    swapchain_semaphore: VkSemaphore;
    render_semaphore: VkSemaphore;
    fence: VkFence;
}

get_current_frame_data :: () -> *Frame_Data {
    return *command_frames[frame % command_frames.count.(u64)];
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// static data

// context
vk_instance: VkInstance;
// representation of hardware
physical_device: Physical_Device;
// gpu driver / logical interface
logical_device: VkDevice;
// queue to which command buffers are passed. a command buffer is just a buffer... of gpu command(s) (and maybe also associated data?)
graphics_queue: VkQueue;
// an abstraction of the drawing surface / window. unnecessary if not drawing to a window.
surface: VkSurfaceKHR;
// a series of render targets and information about them. the images that will be drawn to and presented at the same time.
swapchain: Swapchain;

command_frames: []Frame_Data;

frame: u64;

// eh
test_pipeline_layout: VkPipelineLayout;

init_success := true;

// jai will null-terminate statically allocoated 'string' values and '*u8' values, but the strings in a []string
// don't appear to be null-terminated, thus the (*u8).[] arrays

#if ENABLE_VALIDATION_LAYERS {
    required_layers := (*u8).[
        "VK_LAYER_KHRONOS_validation",
    ];
} else {
    required_layers := (*u8).[];
}

required_instance_extensions := (*u8).[
    "VK_KHR_surface",
    "VK_KHR_win32_surface",
    "VK_KHR_get_surface_capabilities2",
    "VK_EXT_surface_maintenance1",
];

required_device_extensions := (*u8).[
    "VK_KHR_swapchain",
    "VK_EXT_swapchain_maintenance1",
];

#import "vulkan-jai";

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// test shader zone

ONE_MILLISECOND_IN_NANSOSECONDS :: 1_000_000;
ONE_SECOND_IN_NANOSECONDS :: 1_000_000_000;

test_vertex_shader := #string HERE
#version 450

vec2 positions[3] = vec2[](
    vec2(0.0, -0.5),
    vec2(0.5, 0.5),
    vec2(-0.5, 0.5)
);

void main() {
    gl_Position = vec4(positions[gl_VertexIndex], 0.0, 1.0);
}
HERE

test_fragment_shader := #string HERE
#version 450

layout(location = 0) out vec4 outColor;

void main() {
    outColor = vec4(1.0, 0.0, 0.0, 1.0);
}
HERE