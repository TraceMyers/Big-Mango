/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// config

UNLIT :: false;
ENABLE_VALIDATION_LAYERS :: true;

LINES_MAX :: 65_536;
MESHES_MAX :: 4096;

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
// - a combined immage sampler is where the image and the sampler are.. combined. SAMPLED_IMAGE, I guess
// you store once, and create multiple samplers.


// TODO: I *think* uniforms are aligned to 16 bytes, soo.....
// TODO: custom validation layer callback
// TODO: if graphics and present end up with different queues, validation complains about things I don't understand / haven't looked into
// TODO: to fix the above thing, I can probably just reference the main vulkan tutorial
// TODO: do I have to recreate the views when I remake a swapchain?
// TODO: need non-vsync present mode. otherwise, I can't see performance problems coming from afar.
// TODO: it might be better to have one big descriptor pool
// TODO: learn about gamma correction and why it's necessary to display the image as intended. put gamma into the post-processing shader rather than doing it in the exture sampler. (NOTE: no longer using srgb render target, so...?)
// TODO: drawing a 3d shape (say, a capsule) could work like this:
//      1. a capsule is just a line segment with radius. 
//      2. transform the line segment into screenspace.
//      3. use the piecewise min and maxs to get a 2d box. this selects the work groups.
//      4. checking whether or not to draw at a certain fragment is as easy as checking 2d distance from the screenspace line segment against the screenspace radius of the capsule
//      5. depth test and alpha mix fragments during draw
// TODO: angle-weighted normals is a way to apparently get better normals on the vertices for interpolating between them.

_vulkan :: (stage: Boot_Stage) -> bool {
    if stage == .STARTUP {
        // ----------------------------------------------------------------------------------------------------- startup
        pre_init();
        if init_success then create_vk_instance();
        if init_success then create_surface();
        if init_success then select_physical_device();
        if init_success then create_logical_device();
        if init_success then load_extra_procedures();
        if init_success then create_allocator();
        if init_success then create_swapchain();
        if init_success then create_draw_image();
        if init_success then create_depth_image();
        if init_success then create_frame_data();
        if init_success then create_experimental_data();
        if init_success then create_descriptors();
        if init_success then create_pipelines();
        if init_success then create_buffers();
        if init_success then create_primitives();
        return init_success;
    } else {
        // ---------------------------------------------------------------------------------------------------- shutdown
        if !init_success then return false;
        vkDeviceWaitIdle(logical_device);

        for command_frames {
            vkDestroyCommandPool(logical_device, it.command_pool, null);
            vkDestroyFence(logical_device, it.fence, null);
            vkDestroySemaphore(logical_device, it.render_semaphore, null);
            vkDestroySemaphore(logical_device, it.swapchain_semaphore, null);
            flush_deletion_queue(it.deletion_queue, true);
        }
        array_reset(*command_frames);
        array_reset_keeping_memory(*shader_hash_table);

        if draw_image_descriptor_layout {
            vkDestroyDescriptorSetLayout(logical_device, draw_image_descriptor_layout, null);
            draw_image_descriptor_layout = null;
        }
        if draw_image.vk_obj {
            vmaDestroyImage(vk_allocator, draw_image.vk_obj, draw_image.allocation);
            draw_image.vk_obj = null;
        }
        if draw_image.image_view {
            vkDestroyImageView(logical_device, draw_image.image_view, null);
            draw_image.image_view = null;
        }
        if depth_image.vk_obj {
            vmaDestroyImage(vk_allocator, depth_image.vk_obj, depth_image.allocation);
            depth_image.vk_obj = null;
        }
        if depth_image.image_view {
            vkDestroyImageView(logical_device, depth_image.image_view, null);
            depth_image.image_view = null;
        }
        reset(*swapchain);

        flush_deletion_queue(game_deletion_queue, true);

        vkDestroyDevice(logical_device, null);
        logical_device = null;
        vkDestroySurfaceKHR(vk_instance, surface, null);
        surface = null;
        vkDestroyInstance(vk_instance, null);
        vk_instance = null;
        return true;
    }
}

should_rebuild_swapchain :: () -> bool {
    window_dimensions := get_window_dimensions();
    if swapchain.extent.width != xx window_dimensions.x || swapchain.extent.height != xx window_dimensions.y {
        return true;
    } else return false;
}

render_frame :: () {
    if !init_success {
        return;
    }
    if quit {
        return;
    }

    current_frame := get_current_frame_data();
    vk_validate(vkWaitForFences(logical_device, 1, *current_frame.fence, VK_TRUE, ONE_SECOND_IN_NANOSECONDS), "failed to wait for the render fence");
    vk_validate(vkResetFences(logical_device, 1, *current_frame.fence), "failed to reset the render fence");

    if should_rebuild_swapchain() {
        immediate_submit();
        vkQueueWaitIdle(transfer_queue);
        vkQueueWaitIdle(graphics_queue);
        create_swapchain();
        create_draw_image();
        create_depth_image();
        update_draw_image_descriptor_set();
        if !vk_validate(init_success, "failed to recreate the swapchain.") {
            quit = true;
            return;
        }
    }

    image_index := acquire_next_swapchain_image(current_frame);
    flush_deletion_queue(current_frame.deletion_queue);
    render_target := swapchain.images[image_index];
    render_target_view := swapchain.image_views[image_index];

    draw_extent.width = draw_image.extent.width;
    draw_extent.height = draw_image.extent.height;

    viewport := Vector2.{xx draw_image.extent.width, xx draw_image.extent.height};

    prepare_lights();

    immediate_submit();

    render_begin_time := seconds_since_init();

    cmd := begin_command_buffer(current_frame);

    // -----------------------------------------------------------------------------------------------------------------
    // compute draw
    // -----------------------------------------------------------------------------------------------------------------
    transition_image(cmd, draw_image.vk_obj, .UNDEFINED, .GENERAL);

    // -----------------------------------------------------------------------------------------------------------------
    // graphics pipeline draw
    // -----------------------------------------------------------------------------------------------------------------
    transition_image(cmd, draw_image.vk_obj, .GENERAL, .COLOR_ATTACHMENT_OPTIMAL);
    begin_rendering(cmd);

    vp_mat := Matrix4_Identity;
    if context.world != null {
        camera := get_world_main_camera(context.world);
        if camera != null {
            vp_mat = view_projection_matrix(camera, viewport);
        }
    }

    // ship line draws to line draw buffer
    if lines.count > 0 {
        copy_cpu_memory_to_buffer(line_vbo.buffer, as_string(lines));
    }
    defer array_reset_keeping_memory(*lines);

    draw_lines(cmd, *vp_mat);
    draw_spheres(cmd, *vp_mat);

    add_world_draw_commands(cmd, context.world, vp_mat);

    vkCmdEndRendering(cmd);

    // -----------------------------------------------------------------------------------------------------------------
    // more compute
    // -----------------------------------------------------------------------------------------------------------------
    transition_image(cmd, draw_image.vk_obj, .COLOR_ATTACHMENT_OPTIMAL, .GENERAL);

    // -----------------------------------------------------------------------------------------------------------------
    // copy depth stencil to draw image (how????)
    // -----------------------------------------------------------------------------------------------------------------
    // transition_depth_image_for_compute_copy(cmd, depth_image.vk_obj, .UNDEFINED, .SHADER_READ_ONLY_OPTIMAL, .DEPTH_BIT | .STENCIL_BIT);
    // copy_depth_image_to_draw_image(cmd);
    // transition_image(cmd, depth_image.vk_obj, .SHADER_READ_ONLY_OPTIMAL, .DEPTH_STENCIL_READ_ONLY_OPTIMAL, .DEPTH_BIT | .STENCIL_BIT);

    // -----------------------------------------------------------------------------------------------------------------
    // copy graphics to swapchain
    // -----------------------------------------------------------------------------------------------------------------
    transition_image(cmd, draw_image.vk_obj, .GENERAL, .TRANSFER_SRC_OPTIMAL);
    transition_image(cmd, render_target, .UNDEFINED, .TRANSFER_DST_OPTIMAL);
    copy_image(cmd, render_target, draw_image.vk_obj, swapchain.extent, (*depth_image.extent).(*VkExtent2D).*);

    // -----------------------------------------------------------------------------------------------------------------
    // imgui draws directly to the swapchain
    // -----------------------------------------------------------------------------------------------------------------
    transition_image(cmd, render_target, .TRANSFER_DST_OPTIMAL, .COLOR_ATTACHMENT_OPTIMAL);
    vk_draw_imgui(cmd, render_target_view);
    transition_image(cmd, render_target, .COLOR_ATTACHMENT_OPTIMAL, .PRESENT_SRC_KHR);

    // -----------------------------------------------------------------------------------------------------------------
    // clear / prepare for immediated draws
    // -----------------------------------------------------------------------------------------------------------------
    transition_image(cmd, draw_image.vk_obj, .TRANSFER_SRC_OPTIMAL, .GENERAL);
    clear_image(cmd, draw_image.vk_obj);
    transition_image(cmd, draw_image.vk_obj, .GENERAL, .COLOR_ATTACHMENT_OPTIMAL);

    // -----------------------------------------------------------------------------------------------------------------
    // submit and present
    // -----------------------------------------------------------------------------------------------------------------
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

    render_end_time := seconds_since_init();
    target_dt : float = xx (render_end_time - render_begin_time);
    render_dt = exponential_interp(render_dt, target_dt, 2.0, delta_time);
}


// #scope_file // ------------------------------------------------------------------------------------------------ { FILE }

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// tick:15

begin_rendering :: (cmd: VkCommandBuffer) {
    color_attachment := VkRenderingAttachmentInfo.{
        // sType:              VkStructureType = .RENDERING_ATTACHMENT_INFO;
        // pNext:              *void;
        imageView = draw_image.image_view,
        imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
        // resolveMode:        VkResolveModeFlagBits;
        // resolveImageView:   VkImageView;
        // resolveImageLayout: VkImageLayout;
        loadOp = .LOAD,
        storeOp = .STORE,
        // clearValue:         VkClearValue;
    };

    depth_attachment := VkRenderingAttachmentInfo.{
        imageView = depth_image.image_view,
        imageLayout = .DEPTH_ATTACHMENT_OPTIMAL,
        loadOp = .CLEAR,
        storeOp = .STORE,
        clearValue.depthStencil = .{1.0, 0}
    };

    rendering_info := VkRenderingInfo.{
        // pNext:                *void;
        // flags:                VkRenderingFlags;
        renderArea = .{
            .{0,0},
            draw_extent,
        },
        layerCount = 1,
        // viewMask:             u32;
        colorAttachmentCount = 1,
        pColorAttachments = *color_attachment,
        pDepthAttachment = *depth_attachment,
        // pStencilAttachment:   *VkRenderingAttachmentInfo;
    };
    viewport := VkViewport.{
        x = 0,
        y = 0,
        width = xx draw_extent.width,
        height = xx draw_extent.height,
        minDepth = 0.0,
        maxDepth = 1.0
    };
    scissor := VkRect2D.{
        .{0,0},
        draw_extent
    };
    vkCmdSetViewport(cmd, 0, 1, *viewport);
    vkCmdSetScissor(cmd, 0, 1, *scissor);
    vkCmdBeginRendering(cmd, *rendering_info);
}

transition_image :: (cmd: VkCommandBuffer, image: VkImage, old_layout: VkImageLayout, new_layout: VkImageLayout, force_aspect_mask: VkImageAspectFlags = 0) {
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

    if force_aspect_mask != 0 then {
        image_barrier.subresourceRange.aspectMask = force_aspect_mask;
    }

    dependency_info := VkDependencyInfo.{
        imageMemoryBarrierCount = 1,
        pImageMemoryBarriers = *image_barrier
    };

    vkCmdPipelineBarrier2(cmd, *dependency_info);
}

transition_depth_image_for_compute_copy :: (cmd: VkCommandBuffer, image: VkImage, old_layout: VkImageLayout, new_layout: VkImageLayout, force_aspect_mask: VkImageAspectFlags = 0) {
    image_barrier := VkImageMemoryBarrier2.{
        srcStageMask = xx VkPipelineStageFlagBits.LATE_FRAGMENT_TESTS_BIT,
        srcAccessMask = xx VkAccessFlagBits.DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
        dstStageMask = xx VkPipelineStageFlagBits.COMPUTE_SHADER_BIT,
        dstAccessMask = xx VkAccessFlagBits.SHADER_READ_BIT,
        oldLayout = old_layout,
        newLayout = new_layout,
        subresourceRange = .{
            aspectMask = ifx new_layout == .DEPTH_ATTACHMENT_OPTIMAL then .DEPTH_BIT else .COLOR_BIT, 
            baseMipLevel = 0,
            levelCount = 1,
            baseArrayLayer = 0,
            layerCount = 1
        },
        image = image
    };

    if force_aspect_mask != 0 then {
        image_barrier.subresourceRange.aspectMask = force_aspect_mask;
    }

    dependency_info := VkDependencyInfo.{
        imageMemoryBarrierCount = 1,
        pImageMemoryBarriers = *image_barrier
    };

    vkCmdPipelineBarrier2(cmd, *dependency_info);
}

clear_image :: (cmd: VkCommandBuffer, target: VkImage) {
    if draw_extent.width == 0 || draw_extent.height == 0 then return;
    push_constants := Rect_Draw.{
        clear_color,
        .{0,0},
        .{xx draw_extent.width, xx draw_extent.height},
    };

    vkCmdBindPipeline(cmd, .COMPUTE, rect_pipeline);
    vkCmdBindDescriptorSets(cmd, .COMPUTE, rect_pipeline_layout, 0, 1, *draw_image_descriptors, 0, null);
    vkCmdPushConstants(cmd, rect_pipeline_layout, .COMPUTE_BIT, 0, size_of(Rect_Draw), *push_constants);
    vkCmdDispatch(cmd, xx ceil(xx draw_extent.width / 32.0), xx ceil(xx draw_extent.height / 32.0), 1);
}

test_draw_textured_image :: (cmd: VkCommandBuffer, target: VkImage) {
    if draw_extent.width == 0 || draw_extent.height == 0 then return;
    // push_constants := Vector2.[
    //     .{0, 0},
    //     .{1200, 675}
    // ];
    // vkCmdBindPipeline(cmd, .COMPUTE, tex_pipeline);
    // descriptors := VkDescriptorSet.[
    //     draw_image_descriptors,
    //     test_tex_descriptors
    // ];
    // vkCmdBindDescriptorSets(cmd, .COMPUTE, tex_pipeline_layout, 0, xx descriptors.count, descriptors.data, 0, null);
    // vkCmdPushConstants(cmd, tex_pipeline_layout, .COMPUTE_BIT, 0, size_of(Vector2) * 2, *push_constants);
    // vkCmdDispatch(cmd, xx ceil(push_constants[1].x/32.0), xx ceil(push_constants[1].y/32.0), 1);
}

begin_command_buffer :: (frame: *Frame_Data) -> VkCommandBuffer {
    cmd := frame.command_buffer;
    begin_command_buffer(cmd);
    return cmd;
}

begin_command_buffer :: (cmd: VkCommandBuffer) {
    vk_validate(vkResetCommandBuffer(cmd, 0), "failed to reset the main command buffer");
    command_buffer_begin := VkCommandBufferBeginInfo.{flags = .ONE_TIME_SUBMIT_BIT};
    vk_validate(vkBeginCommandBuffer(cmd, *command_buffer_begin), "failed to begin the main command buffer");
}

acquire_next_swapchain_image :: (current_frame: *Frame_Data) -> u32 {
    image_index: u32;
    vk_validate(vkAcquireNextImageKHR(logical_device, swapchain.vk_obj, ONE_SECOND_IN_NANOSECONDS, current_frame.swapchain_semaphore, null, *image_index), "failed to wait to get an image from the swapchain");
    return image_index;
}

vk_draw_imgui :: (cmd: VkCommandBuffer, view: VkImageView) {
    color_attachment := rendering_attachment_info(view, null, .COLOR_ATTACHMENT_OPTIMAL);
    rendering_info := VkRenderingInfo.{
        renderArea = .{
            .{0,0},
            draw_extent,
        },
        layerCount = 1,
        colorAttachmentCount = 1,
        pColorAttachments = *color_attachment,
    };
    vkCmdBeginRendering(cmd, *rendering_info);
    ImGui.ImplVulkan_RenderDrawData(ImGui.GetDrawData(), cmd);
    vkCmdEndRendering(cmd);
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// initialize

pre_init :: () {
    array_reserve(*game_deletion_queue, 2048);
    program_runtime_reserve(*shader_hash_table, 1024);
}

create_vk_instance :: () {
    auto_release_temp();

    vk_init_validate(instance_extensions_are_supported(required_instance_extensions), "required instance extensions unsupported");

    no_validation := !ENABLE_VALIDATION_LAYERS;
    layers_supported := layers_are_supported(required_layers);
    vk_init_validate(no_validation || layers_supported, "the required validation layers are not supported");

    app_info := VkApplicationInfo .{
        pApplicationName = "Big Mango",
        applicationVersion = VK_MAKE_VERSION(0,1,0),
        pEngineName = "Red_Mango",
        engineVersion = VK_MAKE_VERSION(0,1,0),
        apiVersion = VK_API_VERSION
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

load_extra_procedures :: () {
    // vkGetDeviceProcAddr(logical_device, "vkCmdPushConstants");
}

create_surface :: () {
    create_info := VkWin32SurfaceCreateInfoKHR.{
        hwnd = window,
        hinstance = Win32.GetModuleHandleW(null)
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
    {
        using enable_device_features;
        fillModeNonSolid = VK_TRUE;
        wideLines = VK_TRUE;
    }

    dynamic_rendering_enable := VkPhysicalDeviceDynamicRenderingFeatures.{
        dynamicRendering = VK_TRUE,
    };
    // note this has extra features I have no idea what they do.
    // the main feature is to be able to deal directly in GPU pointers
    buffer_device_address_enable := VkPhysicalDeviceBufferDeviceAddressFeatures.{
        bufferDeviceAddress = VK_TRUE,
        pNext = *dynamic_rendering_enable
    };
    // enables syncing a fence on present
    maintenance1_enable := VkPhysicalDeviceSwapchainMaintenance1FeaturesEXT.{
        swapchainMaintenance1 = VK_TRUE,
        pNext = *buffer_device_address_enable
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
    vkGetDeviceQueue(logical_device, xx physical_device.transfer_index, 0, *transfer_queue);
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

create_draw_image :: () {
    if draw_image.vk_obj {
        vmaDestroyImage(vk_allocator, draw_image.vk_obj, draw_image.allocation);
    }
    if draw_image.image_view {
        vkDestroyImageView(logical_device, draw_image.image_view, null);
    }

    auto_release_temp();
    
    window_dims := get_window_dimensions();
    draw_image.extent = VkExtent3D.{
        xx window_dims.x,
        xx window_dims.y,
        (1).(u32)
    };

    draw_image.format = .R16G16B16A16_SFLOAT;
    draw_image_usages: VkImageUsageFlags;
    draw_image_usages |= .TRANSFER_SRC_BIT;
    draw_image_usages |= .TRANSFER_DST_BIT;
    draw_image_usages |= .STORAGE_BIT;
    draw_image_usages |= .COLOR_ATTACHMENT_BIT;

    draw_image_info := image_create_info(draw_image.format, draw_image_usages, draw_image.extent);

    image_alloc_info := VmaAllocationCreateInfo.{
        usage = .GPU_ONLY,
        requiredFlags = .DEVICE_LOCAL_BIT
    };

    // TODO: maybe turn image creation into a function
    // fail without helpful error msg when image extent is bad.
    assert(draw_image.extent.width > 0 && draw_image.extent.height > 0);
    vk_init_validate(vmaCreateImage(vk_allocator, *draw_image_info, *image_alloc_info, *draw_image.vk_obj, *draw_image.allocation, null), "failed to create the main image for drawing");
    
    draw_image_view_info := image_view_create_info(draw_image.format, draw_image.vk_obj, .COLOR_BIT);
    vk_init_validate(vkCreateImageView(logical_device, *draw_image_view_info, null, *draw_image.image_view), "failed to create the view of the main image for drawing");
}

create_depth_image :: () {
    if depth_image.vk_obj {
        vmaDestroyImage(vk_allocator, depth_image.vk_obj, depth_image.allocation);
    }
    if depth_image.image_view {
        vkDestroyImageView(logical_device, depth_image.image_view, null);
    }

    auto_release_temp();

    window_dims := get_window_dimensions();
    depth_image.extent = VkExtent3D.{
        xx window_dims.x,
        xx window_dims.y,
        (1).(u32)
    };

    depth_image.format = depth_buffer_format(physical_device.vk_obj);
    depth_image_usages: VkImageUsageFlags;
    depth_image_usages |= .DEPTH_STENCIL_ATTACHMENT_BIT | .SAMPLED_BIT;

    image_alloc_info := VmaAllocationCreateInfo.{
        usage = .GPU_ONLY,
        requiredFlags = .DEVICE_LOCAL_BIT
    };

    assert(depth_image.extent.width > 0 && depth_image.extent.height > 0);

    info := image_create_info(depth_image.format, depth_image_usages, depth_image.extent);

    vk_init_validate(vmaCreateImage(vk_allocator, *info, *image_alloc_info, *depth_image.vk_obj, *depth_image.allocation, null), "failed to create the main image for drawing");
    
    view_info := image_view_create_info(depth_image.format, depth_image.vk_obj, .STENCIL_BIT);
    vk_init_validate(vkCreateImageView(logical_device, *view_info, null, *depth_image.image_view), "failed to create the view of the main image for drawing");
}

copy_to_staging_buffer :: (memory: []u8) -> VkBuffer, VmaAllocation {
    assert(memory.count > 0);

    staging_buffer_alloc: VmaAllocation;
    staging_buffer_alloc_info := VmaAllocationInfo.{};
    staging_buffer_create_info := VmaAllocationCreateInfo.{
        usage = .CPU_TO_GPU,
        flags = .HOST_ACCESS_SEQUENTIAL_WRITE_BIT,
        // usage=.AUTO
    };
    buffer_create_info := VkBufferCreateInfo.{
        usage = .TRANSFER_SRC_BIT,
        size = xx memory.count
    };

    staging_buffer: VkBuffer;
    vk_validate(vmaCreateBuffer(vk_allocator, *buffer_create_info, *staging_buffer_create_info, *staging_buffer, *staging_buffer_alloc, *staging_buffer_alloc_info), "failed to create a staging buffer");

    buf_memory: *void;
    vmaMapMemory(vk_allocator, staging_buffer_alloc, *buf_memory);
    memcpy(buf_memory, memory.data, memory.count);
    vmaUnmapMemory(vk_allocator, staging_buffer_alloc);
    
    return staging_buffer, staging_buffer_alloc;
}

immediate_submit_transfer_queue :: () {
    cmd := transfer_command_buffer;
    vk_validate(vkEndCommandBuffer(cmd), "failed to end the main command buffer");
    cmd_submit_info := command_buffer_submit_info(cmd);
    submit_info := roll_submit_info(*cmd_submit_info, null, null); 
    vk_validate(vkQueueSubmit2(transfer_queue, 1, *submit_info, transfer_fence), "failed to submit transfer commands to the graphics queue");
    vk_validate(vkWaitForFences(logical_device, 1, *transfer_fence, VK_TRUE, 99_999_999_999), "failed to wait for the transfer fence");
    vk_validate(vkResetFences(logical_device, 1, *transfer_fence), "failed to reset the transfer fence");
}

immediate_submit_graphics_queue :: () {
    cmd := immediate_command_buffer;
    vk_validate(vkEndCommandBuffer(cmd), "failed to end the main command buffer");
    cmd_submit_info := command_buffer_submit_info(cmd);
    submit_info := roll_submit_info(*cmd_submit_info, null, null); 
    vk_validate(vkQueueSubmit2(graphics_queue, 1, *submit_info, immediate_fence), "failed to submit transfer commands to the graphics queue");
    vk_validate(vkWaitForFences(logical_device, 1, *immediate_fence, VK_TRUE, 99_999_999_999), "failed to wait for the transfer fence");
    vk_validate(vkResetFences(logical_device, 1, *immediate_fence), "failed to reset the transfer fence");
}

copy_cpu_memory_to_texture :: (img: *Texture, memory: []u8) {
    staging_buffer, staging_buffer_alloc := copy_to_staging_buffer(memory);
    defer vmaDestroyBuffer(vk_allocator, staging_buffer, staging_buffer_alloc);

    cmd := transfer_command_buffer;
    begin_command_buffer(cmd);

    transition_image(cmd, img.vk_obj, .UNDEFINED, .TRANSFER_DST_OPTIMAL);
    copy_buffer_to_image(cmd, img.vk_obj, staging_buffer, .{img.extent.width, img.extent.height});
    transition_image(cmd, img.vk_obj, .TRANSFER_DST_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL);

    immediate_submit_transfer_queue();
}

copy_cpu_memory_to_buffer :: (buffer: VkBuffer, memory: string) {
    staging_buffer, staging_buffer_alloc := copy_to_staging_buffer(as_array(memory, u8));
    defer vmaDestroyBuffer(vk_allocator, staging_buffer, staging_buffer_alloc);

    cmd := immediate_command_buffer;
    begin_command_buffer(cmd);

    copy := VkBufferCopy.{0, 0, xx memory.count};
    vkCmdCopyBuffer(cmd, staging_buffer, buffer, 1, *copy);   

    immediate_submit_graphics_queue();
}

create_graphics_buffer :: (buffer: *VkBuffer, allocation: *VmaAllocation, memory: string, usage: VkBufferUsageFlags, access: VkAccessFlags, stages: VkPipelineStageFlags) {
    assert(buffer.* == null && allocation.* == null); 

    create_info := VkBufferCreateInfo.{
        size = xx memory.count,
        usage = .TRANSFER_DST_BIT | usage,
        sharingMode = .EXCLUSIVE,
        queueFamilyIndexCount = 1,
        pQueueFamilyIndices = *physical_device.transfer_index
    };
    alloc_create_info := VmaAllocationCreateInfo.{
        usage = .GPU_ONLY,
        requiredFlags = .DEVICE_LOCAL_BIT,
    };
    alloc_info := VmaAllocationInfo.{};
    vmaCreateBuffer(vk_allocator, *create_info, *alloc_create_info, buffer, allocation, *alloc_info);

    // metaprogramming quirk. must directly pass the data that is going into the deferred call. VkBuffer is a ptr type.
    // *VkBuffer is a ptr to that ptr. we need to pass the VkBuffer, not the *VkBuffer.
    _buffer := buffer.*;
    _allocation := allocation.*;
    deletion_queue_add(*game_deletion_queue, vmaDestroyBuffer(vk_allocator, _buffer, _allocation), _buffer, _allocation);

    cmd := transfer_command_buffer;
    begin_command_buffer(cmd);

    staging_buffer: VkBuffer;
    staging_buffer_alloc: VmaAllocation;
    if memory.data != null {
        staging_buffer, staging_buffer_alloc = copy_to_staging_buffer(as_array(memory, u8));
        copy := VkBufferCopy.{0, 0, xx memory.count};
        vkCmdCopyBuffer(cmd, staging_buffer, buffer.*, 1, *copy);   
    }
    defer if memory.data != null then vmaDestroyBuffer(vk_allocator, staging_buffer, staging_buffer_alloc);

    transition_src_queue_index := VK_QUEUE_FAMILY_IGNORED;
    transition_dst_queue_index := VK_QUEUE_FAMILY_IGNORED;
    if physical_device.graphics_index != physical_device.transfer_index {
        transition_src_queue_index = xx physical_device.transfer_index;
        transition_dst_queue_index = xx physical_device.graphics_index;
    }
    buf_release_barrier := VkBufferMemoryBarrier.{
        srcAccessMask = .TRANSFER_WRITE_BIT,
        dstAccessMask = .NONE,
        srcQueueFamilyIndex = transition_src_queue_index,
        dstQueueFamilyIndex = transition_dst_queue_index,
        buffer = buffer.*,
        size = VK_WHOLE_SIZE
    };
    vkCmdPipelineBarrier(cmd, .TRANSFER_BIT, .BOTTOM_OF_PIPE_BIT, 0, 0, null, 1, *buf_release_barrier, 0, null);

    immediate_submit_transfer_queue();

    cmd2 := immediate_command_buffer;
    begin_command_buffer(cmd2);

    buf_acquire_barrier := VkBufferMemoryBarrier.{
        srcAccessMask = .NONE,
        dstAccessMask = access,
        srcQueueFamilyIndex = transition_src_queue_index,
        srcQueueFamilyIndex = transition_dst_queue_index,
        buffer = buffer.*,
        size = VK_WHOLE_SIZE
    };
    vkCmdPipelineBarrier(cmd2, .TOP_OF_PIPE_BIT, stages, 0, 0, null, 1, *buf_acquire_barrier, 0, null);

    immediate_submit_graphics_queue();
}

// null is valid for copy_memory
create_mesh_data_buffer :: (using out_buffer: *Mesh_Data_Buffer, $T: Type, copy_memory: *void, copy_and_allocate_count: s64, $in_type: Mesh_Data_Buffer_Type) 
#modify {
    if in_type == .VERTEX {
        return T == Mesh_Vertex || T == Line_Vertex;
    } else if in_type == .INDEX {
        return T == u16 || T == u32;
    } else {
        return false;
    }
} {
    out_buffer.* = .{};

    type = in_type;
    count = xx copy_and_allocate_count;

    #if in_type == .VERTEX {
        usage_flag := VkBufferUsageFlags.VERTEX_BUFFER_BIT;
        access_flag := VkAccessFlags.VERTEX_ATTRIBUTE_READ_BIT;
    } else {
        usage_flag := VkBufferUsageFlags.INDEX_BUFFER_BIT;
        access_flag := VkAccessFlags.INDEX_READ_BIT;
        #if T == u16 {
            index_type = .U16;
        } else if T == u32 {
            index_type = .U32;
        }
    }

    create_graphics_buffer(*buffer, *allocation, string.{copy_and_allocate_count * size_of(T), copy_memory}, usage_flag, access_flag, .VERTEX_INPUT_BIT);   
}

create_mesh_data_buffer :: inline (using out_buffer: *Mesh_Data_Buffer, memory: []$T, $in_type: Mesh_Data_Buffer_Type) {
    create_mesh_data_buffer(out_buffer, T, memory.data, memory.count, in_type);
}

create_experimental_data :: () {
    {
        img_path := "../content/experimental/pit_puppy.jpg";
        width, height, channels: s32;
        img_memory: []u8;
        img_memory.data = stbi_load(img_path.data, *width, *height, *channels, 4);
        img_memory.count = width * height * 4;
        for 0..(width*height)-1 {
            alpha_i := it * 4 + 3;
            img_memory[alpha_i] = 255;
        }
        create_texture(*test_texture, width, height, *img_memory);

        create_info := VkSamplerCreateInfo.{
            minFilter = .LINEAR,
            magFilter = .LINEAR,
            mipmapMode = .NEAREST,
            addressModeU = .REPEAT,
            addressModeV = .REPEAT,
            addressModeW = .REPEAT,
        };
        vk_init_validate(vkCreateSampler(logical_device, *create_info, null, *test_tex_sampler), "failed to create the test tex sampler");
        deletion_queue_add(*game_deletion_queue, vkDestroySampler(logical_device, test_tex_sampler, null));
    }
    {
        create_info := VkSamplerCreateInfo.{
            minFilter = .NEAREST,
            magFilter = .NEAREST,
            mipmapMode = .NEAREST,
            addressModeU = .REPEAT,
            addressModeV = .REPEAT,
            addressModeW = .REPEAT,
        };
        vk_init_validate(vkCreateSampler(logical_device, *create_info, null, *depth_and_draw_sampler), "failed to create the depth and draw sampler");
        deletion_queue_add(*game_deletion_queue, vkDestroySampler(logical_device, depth_and_draw_sampler, null));
    }
    {
        lights.sun_direction = normalize(Vector3.{0, 0, -1});
        lights.sun_tint = .{1,1,1,1};
        create_graphics_buffer(*lights.buffer, *lights.allocation, as_string(lights.data), .UNIFORM_BUFFER_BIT, .UNIFORM_READ_BIT, .FRAGMENT_SHADER_BIT);
    }
    {
        program_runtime_reserve(*lines, LINES_MAX);
    }
    {
        program_runtime_reserve(*meshes, MESHES_MAX);
    }
}

create_pipelines :: () {
    create_rect_pipeline();
    // create_sphere_pipeline();
    // create_capsule_pipeline();
    // create_tex_pipeline();
    create_graphics_pipeline();
    create_line_pipeline();
    create_copy_depth_image_pipeline();
    if !init_success then return;
}

create_buffers :: () {
    {
        assert(lines.allocated > 0);
        create_mesh_data_buffer(*line_vbo, Line_Vertex, null, lines.allocated * 2, .VERTEX);
    }
}

create_primitives :: () {
    {
        // plane_mesh = create_mesh("_plane", plane_vertices, plane_indices);
        // plane_mesh.primitive_type = .RECT;
    }
    {
        // cube_mesh = create_mesh("_cube", cube_vertices, cube_indices);
        // cube_mesh.primitive_type = .BOX;
    }
    {
        SPHERE_RADIUS :: 1.0;
        sphere_mesh_low_poly = get_or_create_capsule_mesh(SPHERE_RADIUS*2.0, SPHERE_RADIUS, 0.8);
        sphere_mesh_low_poly.primitive_type = .SPHERE;
        sphere_mesh_mid_poly = get_or_create_capsule_mesh(SPHERE_RADIUS*2.0, SPHERE_RADIUS, 0.2);
        sphere_mesh_mid_poly.primitive_type = .SPHERE;
        sphere_mesh_high_poly = get_or_create_capsule_mesh(SPHERE_RADIUS*2.0, SPHERE_RADIUS, 0.05);
        sphere_mesh_high_poly.primitive_type = .SPHERE;
    }
}

create_rect_pipeline :: () {
    push_constant_description := VkPushConstantRange.{
        stageFlags = .COMPUTE_BIT,
        size = size_of(Rect_Draw),
    };
    compute_layout := VkPipelineLayoutCreateInfo.{
        setLayoutCount = 1,
        pSetLayouts = *draw_image_descriptor_layout,
        pushConstantRangeCount = 1,
        pPushConstantRanges = *push_constant_description
    };

    vk_init_validate(vkCreatePipelineLayout(logical_device, *compute_layout, null, *rect_pipeline_layout), "failed to create the bg rect pipeline layout");
    deletion_queue_add(*game_deletion_queue, vkDestroyPipelineLayout(logical_device, rect_pipeline_layout, null));

    compute_draw_shader := load_shader("cmp_draw_rect");

    shader_stage_info := VkPipelineShaderStageCreateInfo.{
        stage = .COMPUTE_BIT,
        module = compute_draw_shader,
        pName = "main"
    };

    compute_pipeline_info := VkComputePipelineCreateInfo.{
        layout = rect_pipeline_layout,
        stage = shader_stage_info
    };

    vk_init_validate(vkCreateComputePipelines(logical_device, VK_NULL_HANDLE, 1, *compute_pipeline_info, null, *rect_pipeline), "failed to create the bg draw pipeline");
    deletion_queue_add(*game_deletion_queue, vkDestroyPipeline(logical_device, rect_pipeline, null));
}

create_copy_depth_image_pipeline :: () {
    compute_layout := VkPipelineLayoutCreateInfo.{
        setLayoutCount = 1,
        pSetLayouts = *depth_and_draw_descriptor_layout,
        pushConstantRangeCount = 0,
        pPushConstantRanges = null
    };

    vk_init_validate(vkCreatePipelineLayout(logical_device, *compute_layout, null, *copy_depth_image_pipeline_layout), "failed to create the bg rect pipeline layout");
    deletion_queue_add(*game_deletion_queue, vkDestroyPipelineLayout(logical_device, copy_depth_image_pipeline_layout, null));

    compute_draw_shader := load_shader("copy_depth_image");

    shader_stage_info := VkPipelineShaderStageCreateInfo.{
        stage = .COMPUTE_BIT,
        module = compute_draw_shader,
        pName = "main"
    };

    compute_pipeline_info := VkComputePipelineCreateInfo.{
        layout = copy_depth_image_pipeline_layout,
        stage = shader_stage_info
    };

    vk_init_validate(vkCreateComputePipelines(logical_device, VK_NULL_HANDLE, 1, *compute_pipeline_info, null, *copy_depth_image_pipeline), "failed to create the bg draw pipeline");
    deletion_queue_add(*game_deletion_queue, vkDestroyPipeline(logical_device, copy_depth_image_pipeline, null));
}

create_sphere_pipeline :: () {
    push_constant_description := VkPushConstantRange.{
        stageFlags = .COMPUTE_BIT,
        size = size_of(float) * 6,
    };
    compute_layout := VkPipelineLayoutCreateInfo.{
        setLayoutCount = 1,
        pSetLayouts = *draw_image_descriptor_layout,
        pushConstantRangeCount = 1,
        pPushConstantRanges = *push_constant_description
    };

    vk_init_validate(vkCreatePipelineLayout(logical_device, *compute_layout, null, *sphere_pipeline_layout), "failed to create the sphere rect pipeline layout");
    deletion_queue_add(*game_deletion_queue, vkDestroyPipelineLayout(logical_device, sphere_pipeline_layout, null));

    compute_draw_shader := load_shader("compute_sphere");

    shader_stage_info := VkPipelineShaderStageCreateInfo.{
        stage = .COMPUTE_BIT,
        module = compute_draw_shader,
        pName = "main"
    };

    compute_pipeline_info := VkComputePipelineCreateInfo.{
        layout = sphere_pipeline_layout,
        stage = shader_stage_info
    };

    vk_init_validate(vkCreateComputePipelines(logical_device, VK_NULL_HANDLE, 1, *compute_pipeline_info, null, *sphere_pipeline), "failed to create the sphere draw pipeline");
    deletion_queue_add(*game_deletion_queue, vkDestroyPipeline(logical_device, sphere_pipeline, null));
}

create_capsule_pipeline :: () {
    push_constant_description := VkPushConstantRange.{
            stageFlags = .COMPUTE_BIT,
            size = size_of(Capsule_Draw_Push_Constants)
    };
    layout := VkPipelineLayoutCreateInfo.{
        setLayoutCount = 1,
        pSetLayouts = *draw_image_descriptor_layout,
        pushConstantRangeCount = 1,
        pPushConstantRanges = *push_constant_description
    };

    vk_init_validate(vkCreatePipelineLayout(logical_device, *layout, null, *capsule_pipeline_layout), "failed to create the sphere rect pipeline layout");
    deletion_queue_add(*game_deletion_queue, vkDestroyPipelineLayout(logical_device, capsule_pipeline_layout, null));

    compute_draw_shader := load_shader("compute_draw_capsule");

    shader_stage_info := VkPipelineShaderStageCreateInfo.{
        stage = .COMPUTE_BIT,
        module = compute_draw_shader,
        pName = "main"
    };

    compute_pipeline_info := VkComputePipelineCreateInfo.{
        layout = capsule_pipeline_layout,
        stage = shader_stage_info
    };

    vk_init_validate(vkCreateComputePipelines(logical_device, VK_NULL_HANDLE, 1, *compute_pipeline_info, null, *capsule_pipeline), "failed to create the sphere draw pipeline");
    deletion_queue_add(*game_deletion_queue, vkDestroyPipeline(logical_device, capsule_pipeline, null));
}

create_tex_pipeline :: () {
    push_constant_description := VkPushConstantRange.{
        stageFlags = .COMPUTE_BIT,
        size = size_of(Vector2) * 2,
    };
    layouts := VkDescriptorSetLayout.[
        draw_image_descriptor_layout,
        test_tex_descriptor_layout
    ];
    compute_layout := VkPipelineLayoutCreateInfo.{
        setLayoutCount = xx layouts.count,
        pSetLayouts = layouts.data,
        pushConstantRangeCount = 1,
        pPushConstantRanges = *push_constant_description
    };

    vk_init_validate(vkCreatePipelineLayout(logical_device, *compute_layout, null, *tex_pipeline_layout), "failed to create a pipeline layout");
    deletion_queue_add(*game_deletion_queue, vkDestroyPipelineLayout(logical_device, tex_pipeline_layout, null));

    compute_draw_shader := load_shader("cpt_draw_quad_textured");
    vk_init_validate(compute_draw_shader != null, "failed to create a shader");

    shader_stage_info := VkPipelineShaderStageCreateInfo.{
        stage = .COMPUTE_BIT,
        module = compute_draw_shader,
        pName = "main"
    };

    compute_pipeline_info := VkComputePipelineCreateInfo.{
        layout = tex_pipeline_layout,
        stage = shader_stage_info
    };

    vk_init_validate(vkCreateComputePipelines(logical_device, VK_NULL_HANDLE, 1, *compute_pipeline_info, null, *tex_pipeline), "failed to create the a pipeline");
    deletion_queue_add(*game_deletion_queue, vkDestroyPipeline(logical_device, tex_pipeline, null));

    vkDestroyShaderModule(logical_device, compute_draw_shader, null);
}

create_graphics_pipeline :: () {
    auto_release_temp();

    test_frag := ifx UNLIT then load_shader("unlit_color_mesh_frag") else load_shader("color_mesh_frag");
    test_vert := load_shader("color_mesh_vert");

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

    vertex_bindings, vertex_attributes := vertex_descriptors(Mesh_Vertex);

    vertex_input_info := VkPipelineVertexInputStateCreateInfo.{
        vertexBindingDescriptionCount = 1,
        pVertexBindingDescriptions = *vertex_bindings,
        vertexAttributeDescriptionCount = xx vertex_attributes.count,
        pVertexAttributeDescriptions = vertex_attributes.data
    };

    input_assembly_info := VkPipelineInputAssemblyStateCreateInfo.{
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

    viewport_create_info := VkPipelineViewportStateCreateInfo.{
        viewportCount = 1,
        scissorCount = 1
    };

    rasterizer_create_info := VkPipelineRasterizationStateCreateInfo.{
        depthClampEnable = VK_FALSE,
        rasterizerDiscardEnable = VK_FALSE,
        polygonMode = .FILL,
        lineWidth = 1.0,
        // cullMode = .FRONT_BIT,
        // cullMode = .BACK_BIT,
        cullMode = .NONE,
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
        blendEnable = VK_TRUE,
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

    dynamic_states := VkDynamicState.[
        .VIEWPORT,
        .SCISSOR,
        // .LINE_WIDTH,
        // .DEPTH_BIAS,
        // .BLEND_CONSTANTS,
        // .DEPTH_BOUNDS,
        // .STENCIL_COMPARE_MASK             :: 6;
        // .STENCIL_WRITE_MASK               :: 7;
        // .STENCIL_REFERENCE                :: 8;
        // .VIEWPORT_W_SCALING_NV            :: 1000087000;
        // .DISCARD_RECTANGLE_EXT            :: 1000099000;
        // SAMPLE_LOCATIONS_EXT             :: 1000143000;
    ];

    dynamic_state := VkPipelineDynamicStateCreateInfo.{
        dynamicStateCount = xx dynamic_states.count,
        pDynamicStates = dynamic_states.data
    };

    layouts := VkDescriptorSetLayout.[
        mesh_descriptor_set_layout,
    ];

    color_pc := VkPushConstantRange.{
        stageFlags = .VERTEX_BIT,
        offset = 0,
        size = size_of(float32) * 16 + size_of(float32) * 4 + size_of(float) * 4
    };

    pipeline_layout_info := VkPipelineLayoutCreateInfo.{
        setLayoutCount = xx layouts.count,
        pSetLayouts = layouts.data,
        pushConstantRangeCount = 1,
        pPushConstantRanges = *color_pc
    };

    vk_init_validate(vkCreatePipelineLayout(logical_device, *pipeline_layout_info, null, *graphics_pipeline_layout), "failed to create the graphics pipeline layout");
    deletion_queue_add(*game_deletion_queue, vkDestroyPipelineLayout(logical_device, graphics_pipeline_layout, null));

    color_attachment_format := VkFormat.R16G16B16A16_SFLOAT;
    rendering_create_info := VkPipelineRenderingCreateInfo.{
        colorAttachmentCount=1,
        pColorAttachmentFormats = *color_attachment_format,
        depthAttachmentFormat = .D24_UNORM_S8_UINT
    };

    depth_stencil_info := VkPipelineDepthStencilStateCreateInfo.{
        depthTestEnable = VK_TRUE,
        depthWriteEnable = VK_TRUE,
        depthCompareOp = .LESS,
        depthBoundsTestEnable = VK_FALSE,
        stencilTestEnable = VK_FALSE,
        // front:                 VkStencilOpState;
        // back:                  VkStencilOpState;
        // minDepthBounds:        float;
        // maxDepthBounds:        float;
    };

    pipeline_create := VkGraphicsPipelineCreateInfo.{
        pNext = *rendering_create_info,
        stageCount = xx shader_stages.count,
        pStages = shader_stages.data,
        pVertexInputState = *vertex_input_info,
        pInputAssemblyState = *input_assembly_info,
        // pTessellationState:  *VkPipelineTessellationStateCreateInfo;
        pViewportState = *viewport_create_info,
        pRasterizationState = *rasterizer_create_info,
        pMultisampleState = *multisample_create_info,
        pDepthStencilState = *depth_stencil_info,
        pColorBlendState = *color_blend_create,
        pDynamicState = *dynamic_state,
        layout = graphics_pipeline_layout,
        // renderPass:          VkRenderPass;
        // subpass:             u32;
        // basePipelineHandle:  VkPipeline;
        // basePipelineIndex:   s32;
    };

    vk_init_validate(vkCreateGraphicsPipelines(logical_device, VK_NULL_HANDLE, 1, *pipeline_create, null, *graphics_pipeline), "failed to create the the graphics pipeline");
    deletion_queue_add(*game_deletion_queue, vkDestroyPipeline(logical_device, graphics_pipeline, null));
}

create_line_pipeline :: () {
    auto_release_temp();

    frag := load_shader("line_frag");
    vert := load_shader("line_vert");

    shader_stages := VkPipelineShaderStageCreateInfo.[
     .{
        stage = .VERTEX_BIT,
        module = vert,
        pName = "main"
    }, 
    .{
        stage = .FRAGMENT_BIT,
        module = frag,
        pName = "main"
    }];

    vertex_bindings, vertex_attributes := vertex_descriptors(Line_Vertex);

    vertex_input_info := VkPipelineVertexInputStateCreateInfo.{
        vertexBindingDescriptionCount = 1,
        pVertexBindingDescriptions = *vertex_bindings,
        vertexAttributeDescriptionCount = xx vertex_attributes.count,
        pVertexAttributeDescriptions = vertex_attributes.data
    };

    input_assembly_info := VkPipelineInputAssemblyStateCreateInfo.{
        topology = .LINE_LIST,
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

    viewport_create_info := VkPipelineViewportStateCreateInfo.{
        viewportCount = 1,
        scissorCount = 1
    };

    rasterizer_create_info := VkPipelineRasterizationStateCreateInfo.{
        depthClampEnable = VK_FALSE,
        rasterizerDiscardEnable = VK_FALSE,
        polygonMode = .LINE,
        lineWidth = 1.0,
        // cullMode = .FRONT_BIT,
        // cullMode = .BACK_BIT,
        cullMode = .NONE,
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
        blendEnable = VK_TRUE,
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

    dynamic_states := VkDynamicState.[
        .VIEWPORT,
        .SCISSOR,
        .LINE_WIDTH,
        // .DEPTH_BIAS,
        // .BLEND_CONSTANTS,
        // .DEPTH_BOUNDS,
        // .STENCIL_COMPARE_MASK             :: 6;
        // .STENCIL_WRITE_MASK               :: 7;
        // .STENCIL_REFERENCE                :: 8;
        // .VIEWPORT_W_SCALING_NV            :: 1000087000;
        // .DISCARD_RECTANGLE_EXT            :: 1000099000;
        // SAMPLE_LOCATIONS_EXT             :: 1000143000;
    ];

    dynamic_state := VkPipelineDynamicStateCreateInfo.{
        dynamicStateCount = xx dynamic_states.count,
        pDynamicStates = dynamic_states.data
    };

    layouts := VkDescriptorSetLayout.[
        // mesh_descriptor_set_layout,
    ];

    color_pc := VkPushConstantRange.{
        stageFlags = .VERTEX_BIT,
        offset = 0,
        size = size_of(float32) * 16,
    };

    pipeline_layout_info := VkPipelineLayoutCreateInfo.{
        setLayoutCount = xx layouts.count,
        pSetLayouts = layouts.data,
        pushConstantRangeCount = 1,
        pPushConstantRanges = *color_pc
    };

    vk_init_validate(vkCreatePipelineLayout(logical_device, *pipeline_layout_info, null, *line_pipeline_layout), "failed to create the line pipeline layout");
    deletion_queue_add(*game_deletion_queue, vkDestroyPipelineLayout(logical_device, line_pipeline_layout, null));

    color_attachment_format := VkFormat.R16G16B16A16_SFLOAT;
    rendering_create_info := VkPipelineRenderingCreateInfo.{
        colorAttachmentCount=1,
        pColorAttachmentFormats = *color_attachment_format,
        depthAttachmentFormat = .D24_UNORM_S8_UINT
    };

    depth_stencil_info := VkPipelineDepthStencilStateCreateInfo.{
        depthTestEnable = VK_TRUE,
        depthWriteEnable = VK_TRUE,
        depthCompareOp = .LESS,
        depthBoundsTestEnable = VK_FALSE,
        stencilTestEnable = VK_FALSE,
        // front:                 VkStencilOpState;
        // back:                  VkStencilOpState;
        // minDepthBounds:        float;
        // maxDepthBounds:        float;
    };

    pipeline_create := VkGraphicsPipelineCreateInfo.{
        pNext = *rendering_create_info,
        stageCount = xx shader_stages.count,
        pStages = shader_stages.data,
        pVertexInputState = *vertex_input_info,
        pInputAssemblyState = *input_assembly_info,
        // pTessellationState:  *VkPipelineTessellationStateCreateInfo;
        pViewportState = *viewport_create_info,
        pRasterizationState = *rasterizer_create_info,
        pMultisampleState = *multisample_create_info,
        pDepthStencilState = *depth_stencil_info,
        pColorBlendState = *color_blend_create,
        pDynamicState = *dynamic_state,
        layout = line_pipeline_layout,
        // renderPass:          VkRenderPass;
        // subpass:             u32;
        // basePipelineHandle:  VkPipeline;
        // basePipelineIndex:   s32;
    };

    vk_init_validate(vkCreateGraphicsPipelines(logical_device, VK_NULL_HANDLE, 1, *pipeline_create, null, *line_pipeline), "failed to create the the line pipeline");
    deletion_queue_add(*game_deletion_queue, vkDestroyPipeline(logical_device, line_pipeline, null));
}

create_frame_data :: () {
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
        array_reserve(*command_frames[it].deletion_queue, 2048);
    }

    fence_info.flags = 0;
    {
        vk_init_validate(vkCreateCommandPool(logical_device, *command_pool_info, null, *immediate_command_pool), "failed to create the immediate render command pool");

        buffer_alloc_info := VkCommandBufferAllocateInfo.{
            commandPool = immediate_command_pool,
            commandBufferCount = 1,
            level = .PRIMARY
        };
        vk_init_validate(vkAllocateCommandBuffers(logical_device, *buffer_alloc_info, *immediate_command_buffer), "unable to allocate the immediate render command buffer");
        deletion_queue_add(*game_deletion_queue, vkDestroyCommandPool(logical_device, immediate_command_pool, null));

        vk_init_validate(vkCreateFence(logical_device, *fence_info, null, *immediate_fence), "failed to create the immediate render fence");
        deletion_queue_add(*game_deletion_queue, vkDestroyFence(logical_device, immediate_fence, null));

        begin_command_buffer(immediate_command_buffer);
    }
    {
        pool_info := VkCommandPoolCreateInfo.{
            flags = .RESET_COMMAND_BUFFER_BIT,
            queueFamilyIndex = xx physical_device.transfer_index
        };
        vk_init_validate(vkCreateCommandPool(logical_device, *pool_info, null, *transfer_command_pool), "failed to create the transfer command pool");

        buffer_alloc_info := VkCommandBufferAllocateInfo.{
            commandPool = transfer_command_pool,
            commandBufferCount = 1,
            level = .PRIMARY
        };
        vk_init_validate(vkAllocateCommandBuffers(logical_device, *buffer_alloc_info, *transfer_command_buffer), "failed to create the transfer command pool");
        deletion_queue_add(*game_deletion_queue, vkDestroyCommandPool(logical_device, transfer_command_pool, null));

        vk_init_validate(vkCreateFence(logical_device, *fence_info, null, *transfer_fence), "failed to create the transfer fence");
        deletion_queue_add(*game_deletion_queue, vkDestroyFence(logical_device, transfer_fence, null));
    }
}

create_allocator :: () {
    allocator_info := VmaAllocatorCreateInfo.{
        physicalDevice = physical_device.vk_obj,
        device = logical_device,
        instance = vk_instance,
        // BUFFER_DEVICE_ADDRESS enables the ability to use pointers to gpu data
        // could, for example, pass those pointers into shaders
        flags = .BUFFER_DEVICE_ADDRESS_BIT, 
        vulkanApiVersion = VK_API_VERSION
    };
    vk_init_validate(vmaCreateAllocator(*allocator_info, *vk_allocator), "failed to create an instance of Vulkan Memory Allocator");
    deletion_queue_add(*game_deletion_queue, vmaDestroyAllocator(xx vk_allocator));
}

create_descriptors :: () {
    // pool will hold 10 sets, each with 1 image
    ratios := Descriptor_Pool_Size_Ratio.[.{.STORAGE_IMAGE, 0.2}, .{.COMBINED_IMAGE_SAMPLER, 0.5}, .{.UNIFORM_BUFFER, 0.3}];
    init_pool(*game_descriptor_pool, 10, ratios);
    deletion_queue_add(*game_deletion_queue,  vkDestroyDescriptorPool(logical_device, game_descriptor_pool, null));

    // /////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    bindings := VkDescriptorSetLayoutBinding.[
        .{binding=0, descriptorCount=1, descriptorType=.STORAGE_IMAGE}
    ];
    draw_image_descriptor_layout = build_descriptor_set_layout(bindings, .COMPUTE_BIT);
    draw_image_descriptors = allocate_descriptor_set(game_descriptor_pool, draw_image_descriptor_layout);

    update_draw_image_descriptor_set();

    // /////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    bindings_2 := VkDescriptorSetLayoutBinding.[
        .{binding=0, descriptorCount=1, descriptorType=.COMBINED_IMAGE_SAMPLER}
    ];
    test_tex_descriptor_layout = build_descriptor_set_layout(bindings_2, .COMPUTE_BIT);
    test_tex_descriptors = allocate_descriptor_set(game_descriptor_pool, test_tex_descriptor_layout);

    deletion_queue_add(*game_deletion_queue, vkDestroyDescriptorSetLayout(logical_device, test_tex_descriptor_layout, null));

    {
        info := VkDescriptorImageInfo.{
            sampler = test_tex_sampler,
            imageLayout=.SHADER_READ_ONLY_OPTIMAL,
            imageView=test_texture.image_view
        };
        write := VkWriteDescriptorSet.{
            dstSet = test_tex_descriptors,
            descriptorCount = 1,
            descriptorType = .COMBINED_IMAGE_SAMPLER,
            pImageInfo = *info
        };
        vkUpdateDescriptorSets(logical_device, 1, *write, 0, null);
    }

    // /////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    ubo_layout_bindings := VkDescriptorSetLayoutBinding.[
        .{binding=0, descriptorType = .UNIFORM_BUFFER, descriptorCount = 1, stageFlags = .FRAGMENT_BIT},
        // .{binding=0, descriptorCount=1, descriptorType=.COMBINED_IMAGE_SAMPLER, stageFlags = .FRAGMENT_BIT}
    ];
    mesh_descriptor_set_layout = build_descriptor_set_layout(ubo_layout_bindings, 0);

    deletion_queue_add(*game_deletion_queue, vkDestroyDescriptorSetLayout(logical_device, mesh_descriptor_set_layout, null));

    mesh_descriptors = allocate_descriptor_set(game_descriptor_pool, mesh_descriptor_set_layout);

    {
        info := VkDescriptorBufferInfo.{
            buffer=lights.buffer,
            offset=0,
            range=VK_WHOLE_SIZE
        };
        write := VkWriteDescriptorSet.{
            dstSet = mesh_descriptors,
            descriptorCount = 1,
            descriptorType = .UNIFORM_BUFFER,
            pBufferInfo = *info
        };
        vkUpdateDescriptorSets(logical_device, 1, *write, 0, null);
    }

    depth_layout_bindings := VkDescriptorSetLayoutBinding.[
        .{binding=0, descriptorType=.COMBINED_IMAGE_SAMPLER, descriptorCount=1},
        .{binding=1, descriptorType=.STORAGE_IMAGE, descriptorCount=1},
    ];
    depth_and_draw_descriptor_layout = build_descriptor_set_layout(depth_layout_bindings, .COMPUTE_BIT);
    depth_and_draw_descriptors = allocate_descriptor_set(game_descriptor_pool, depth_and_draw_descriptor_layout);

    deletion_queue_add(*game_deletion_queue, *vkDestroyDescriptorSetLayout(logical_device, depth_and_draw_descriptor_layout, null));

    {
        infos := VkDescriptorImageInfo.[
            .{
                sampler = depth_and_draw_sampler,
                imageLayout=.SHADER_READ_ONLY_OPTIMAL,
                imageView=depth_image.image_view
            }, 
            .{
                imageLayout=.GENERAL,
                imageView=draw_image.image_view
            }
        ];
        writes := VkWriteDescriptorSet.[
            .{
                dstSet=depth_and_draw_descriptors,
                dstBinding=0,
                descriptorCount=1,
                descriptorType=.COMBINED_IMAGE_SAMPLER,
                pImageInfo=*infos[0]
            },
            .{
                dstSet=depth_and_draw_descriptors,
                dstBinding=1,
                descriptorCount=1,
                descriptorType=.STORAGE_IMAGE,
                pImageInfo=*infos[1]
            }
        ];
        vkUpdateDescriptorSets(logical_device, 2, writes.data, 0, null);
    }
}

update_draw_image_descriptor_set :: () {
    info := VkDescriptorImageInfo.{
        imageLayout=.GENERAL,
        imageView = draw_image.image_view
    };
    draw_image_write := VkWriteDescriptorSet.{
        dstBinding = 0,
        dstSet = draw_image_descriptors,
        descriptorCount = 1,
        descriptorType = .STORAGE_IMAGE,
        pImageInfo = *info
    };
    vkUpdateDescriptorSets(logical_device, 1, *draw_image_write, 0, null);
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// runtime

load_shader :: (filename: string, add_to_deletion_queue := true) -> VkShaderModule {
    hash := native_XXH64(filename.data, xx filename.count, 0);
    for shader_hash_table {
        if it.hash == hash {
            return it.shader;
        }
    }
    file_path := tprint("../shaders/intermediate/%.spv", filename);
    shader := create_shader_module_from_file(file_path);
    vk_validate(shader != null, "failed to load shader %", filename);
    array_add(*shader_hash_table, .{hash, shader});
    if add_to_deletion_queue {
        deletion_queue_add(*game_deletion_queue, vkDestroyShaderModule(logical_device, shader, null), shader);
    }

    return shader;
}

create_shader_module_from_file :: (filename: string) -> VkShaderModule {
    auto_release_temp();
    file_data: string;
    {
        scope_set_allocator(temp);
        file_data=, success := read_entire_file(filename, true);
        vk_validate(success, "failed to load shader binary for %", filename);
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

generate_capsule_mesh_name :: (height: float, radius: float, triangulize_distance: float) -> string {
    return tprint("_capsule_%_%_%", height, radius, triangulize_distance);
}

create_capsule_mesh :: (height: float, radius: float, triangulize_distance := 1.0) -> *Mesh {
    auto_release_temp();

    capsule_indices: [..]u16;
    capsule_indices.allocator = temp;
    capsule_vertices: [..]Mesh_Vertex;
    capsule_vertices.allocator = temp;

    generate_capsule_geo(*capsule_vertices, *capsule_indices, height, radius, triangulize_distance);

    capsule_name := generate_capsule_mesh_name(height, radius, triangulize_distance);
    capsule_mesh := create_mesh(capsule_name, capsule_vertices, capsule_indices, .CAPSULE);

    return capsule_mesh;
}

get_or_create_capsule_mesh :: (height: float, radius: float, triangulize_distance := 0.0) -> *Mesh {
    if triangulize_distance == 0 {
        cylinder_side_surface_area := 2 * PI * radius * height;
        sphere_surface_area := 4 * PI * square(radius);
        total_surface_area := cylinder_side_surface_area + sphere_surface_area;
        TARGET_TRIANGLE_COUNT :: 1024;
        triangulize_distance = sqrt(total_surface_area / TARGET_TRIANGLE_COUNT);
    }
    capsule_name := generate_capsule_mesh_name(height, radius, triangulize_distance);
    mesh := get_existing_mesh(capsule_name);
    if mesh == null then mesh = create_capsule_mesh(height, radius, triangulize_distance);
    return mesh;
}

get_existing_mesh :: (name: string) -> *Mesh {
    hash := native_XXH64(name.data, xx name.count, 0);
    for meshes {
        if hash == it.hash then return *it.mesh;
    }
    return null;
}

get_or_create_mesh :: (name: string, vertices: []Mesh_Vertex, indices: []u16) -> *Mesh {
    mesh := get_existing_mesh(name);
    if mesh then return mesh;
    return create_mesh(name, vertices, indices);
}

create_mesh :: (name: string, vertices: []Mesh_Vertex, indices: []u16, primitive_type: Collision_Shape_Type = .NONE) -> *Mesh {
    // just a convention to make sure the preloads are consistent and intentional. all preload names start with an underscore.
    assert(starts_with(name, "_"));

    hash := native_XXH64(name.data, xx name.count, 0);
    for meshes {
        assert(it.hash != hash);
    }   

    auto_release_temp();

    mesh: Mesh;
    modified_vertices: [..]Mesh_Vertex;
    modified_vertices.allocator = temp;

    setup_mesh_data_for_flat_shading(vertices, indices, *modified_vertices);
    create_mesh_data_buffer(*mesh.ibo, indices, .INDEX);
    create_mesh_data_buffer(*mesh.vbo, modified_vertices, .VERTEX);

    mesh.primitive_type = primitive_type;

    array_add(*meshes, .{hash, mesh});
    return *meshes[meshes.count-1].mesh;
}

// $todo: cleanup duplicate
create_mesh :: (name: string, hash: u64, vertices: []Mesh_Vertex, indices: []u16, primitive_type: Collision_Shape_Type = .NONE) -> *Mesh {
    for meshes {
        assert(it.hash != hash);
    }   

    auto_release_temp();

    mesh: Mesh;
    modified_vertices: [..]Mesh_Vertex;
    modified_vertices.allocator = temp;

    setup_mesh_data_for_flat_shading(vertices, indices, *modified_vertices);
    create_mesh_data_buffer(*mesh.ibo, indices, .INDEX);
    create_mesh_data_buffer(*mesh.vbo, modified_vertices, .VERTEX);

    mesh.primitive_type = primitive_type;

    array_add(*meshes, .{hash, mesh});
    return *meshes[meshes.count-1].mesh;
}

// norm translation offsets: x,y,z in -inf, inf where 0,0,0 is no vertex offset, and 0,0,0.5 is a half-mesh-height vertex offset in z
get_or_load_mesh :: (filename: string, flip_winding := false, reorient := Quaternion.{}, norm_translation_offsets := Vector3.{}, add_to_deletion_queue := true, assert_already_loaded := false) -> *Mesh {
    hash := native_XXH64(filename.data, xx filename.count, 0);
    for meshes {
        if it.hash == hash {
            return *it.mesh;
        }
    }
    assert(!assert_already_loaded);

    mesh: Mesh;
    file_path := tprint("../content/%", filename);
    success := load_mesh_from_file(*mesh, file_path, flip_winding, reorient, norm_translation_offsets);
    if !success {
        return null;
    }

    array_add(*meshes, .{hash, mesh});
    if add_to_deletion_queue {
        // deletion_queue_add(*game_deletion_queue, ) // ?
    }

    return *meshes[meshes.count-1].mesh;
}

get_or_load_mesh :: (loader_reference: Asset_Reference) -> *Mesh {
    for meshes {
        if it.hash == loader_reference.name_hash {
            return *it.mesh;
        }
    }

    scope_set_working_directory("../assets");

    // $todo: generic read/write asset info serialization is actually doable piecewise.
    read_success: bool;
    serializer: Serializer(.STATIC, .PRIMITIVE);
    serializer.memory, read_success = read_entire_file(loader_reference.path);
    assert(read_success);

    set_rw_mode(*serializer, .READ, false);
    
    meta_data_version: s32;
    serialize(*serializer, *meta_data_version);

    loader_version: s32;

    if meta_data_version == {
    case 1;
        serializer.head = 0;
        meta_data: Asset_Meta_Data_V1;
        serialize(*serializer, (*meta_data).(*u8), size_of(Asset_Meta_Data_V1));
        assert(meta_data.type == .MESH);
        loader_version = meta_data.version;
    case;
        assert(false, "invalid meta data version %", meta_data_version);
    }

    if loader_version == {
    case 1;
        loader: Mesh_Loader_V1;
        serialize(*serializer, (*loader).(*u8), size_of(Mesh_Loader_V1));
        if loader.load_type == .PRIMITIVE {
            if loader.primitive_type == {
            case .SPHERE;
            case .CAPSULE;
            case .RECT;
                name := path_strip_extension(path_filename(loader_reference.path));
                return create_mesh(name, loader_reference.name_hash, plane_vertices, plane_indices, .RECT);
            case .BOX;
                name := path_strip_extension(path_filename(loader_reference.path));
                return create_mesh(name, loader_reference.name_hash, cube_vertices, cube_indices, .BOX);
            case .AABB;
                name := path_strip_extension(path_filename(loader_reference.path));
                return create_mesh(name, loader_reference.name_hash, cube_vertices, cube_indices, .BOX);
            case .HALF_SPACE;
            case;
                assert(false, "invalid mesh loader primitive type %", loader.load_type);
            } 
        } else { // OBJ
            // $todo: obj load asset
        }
    case;
        assert(false, "invalid mesh loader version %", loader_version);
    }

    return null;
}

load_mesh_from_file :: (out_mesh: *Mesh, file_path: string, flip_winding: bool, reorient := Quaternion.{}, norm_translation_offsets := Vector3.{}) -> bool {
    auto_release_temp();
    out_mesh.* = .{};

    vertices: []Mesh_Vertex;
    indices: Index_Buffer;

    if ends_with(file_path, ".obj") {
        vertices, indices = load_obj_file(file_path, flip_winding, reorient, norm_translation_offsets, temp);
    } else {
        return false;
    }

    modified_vertices: [..]Mesh_Vertex;
    modified_vertices.allocator = temp;

    if indices.type == .U16 {
        setup_mesh_data_for_flat_shading(vertices, indices._u16, *modified_vertices);
        create_mesh_data_buffer(*out_mesh.ibo, indices._u16, .INDEX);
    } else {
        setup_mesh_data_for_flat_shading(vertices, indices._u32, *modified_vertices);
        create_mesh_data_buffer(*out_mesh.ibo, indices._u32, .INDEX);
    }
    create_mesh_data_buffer(*out_mesh.vbo, modified_vertices, .VERTEX);

    return true;
}

// TODO: could maybe use some more params? I guess that'll be obvious later
// according to vkguide.dev, Blit is more flexible (images can have different extents), Copy is faster, and eventually you just want to write your own custom fragment shader so you can do extra things while copying.
copy_image :: (cmd: VkCommandBuffer, dst: VkImage, src: VkImage, dst_dims: VkExtent2D, src_dims: VkExtent2D) {
    blit_region := VkImageBlit2.{
        srcOffsets = .[
            .{}, 
            .{xx src_dims.width, xx src_dims.height, 1}
        ],
        dstOffsets = .[
            .{},
            .{xx dst_dims.width, xx dst_dims.height, 1}
        ],
        srcSubresource = .{
            aspectMask = .COLOR_BIT,
            layerCount = 1
        },
        dstSubresource = .{
            aspectMask = .COLOR_BIT,
            layerCount = 1
        }
    };
    blit_info := VkBlitImageInfo2.{
        dstImage = dst,
        dstImageLayout = .TRANSFER_DST_OPTIMAL,
        srcImage = src,
        srcImageLayout = .TRANSFER_SRC_OPTIMAL,
        filter = .LINEAR,
        regionCount = 1,
        pRegions = *blit_region
    };
    vkCmdBlitImage2(cmd, *blit_info);
}

copy_buffer_to_image :: (cmd: VkCommandBuffer, dst: VkImage, src: VkBuffer, dst_dims: VkExtent2D) {
    copy_region := VkBufferImageCopy.{
        imageSubresource = .{
            aspectMask = .COLOR_BIT,
            layerCount = 1,
        },
        imageExtent = .{dst_dims.width, dst_dims.height, 1}
    };
    vkCmdCopyBufferToImage(cmd, src, dst, .TRANSFER_DST_OPTIMAL, 1, *copy_region);
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// init helpers

// TODO: < 0 error values are total failure, > 0 mean something else. account for this.

vk_init_validate :: (result: $T, error_msg: string, msg_args: ..Any, caller_loc := #caller_location) #expand 
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
    }
}

Vk_Validate_Severity :: enum {
    WARNING_MESSAGE;
    ERROR_MESSAGE;
    ASSERT;
}

vk_validate :: (result: $T, error_msg: string, msg_args: ..Any, $severity := Vk_Validate_Severity.ASSERT, caller_loc := #caller_location) -> bool #expand 
#modify { return T == bool || T == VkResult; } {
    error_code_str: string;
    #if T == VkResult {
        failure := result != .SUCCESS;
        error_code_str = tprint("[VK ERROR: %] ", result);
    } else {
        failure := !result;
    }
    if failure {
        #if severity == .WARNING_MESSAGE {
            rm_warning(tprint("vulkan %:: %", error_code_str, error_msg), ..msg_args, true, caller_loc);
        } else {
            rm_error(tprint("vulkan %:: %", error_code_str, error_msg), ..msg_args, true, caller_loc);
            #if severity == .ASSERT {
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
        bound_array_add(*unique_indices, xx queue_family_indices[it]);
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

depth_buffer_format :: (device: VkPhysicalDevice) -> VkFormat {
    props: VkFormatProperties;
    vkGetPhysicalDeviceFormatProperties(device, .D24_UNORM_S8_UINT, *props);
    if (props.optimalTilingFeatures & .DEPTH_STENCIL_ATTACHMENT_BIT) != 0 {
        return .D24_UNORM_S8_UINT;
    }
    vkGetPhysicalDeviceFormatProperties(device, .D32_SFLOAT_S8_UINT, *props);
    if (props.optimalTilingFeatures & .DEPTH_STENCIL_ATTACHMENT_BIT) != 0 {
        return .D32_SFLOAT_S8_UINT;
    }
    return .UNDEFINED;
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
    if !features.fillModeNonSolid {
        return 0;
    }
    dummy_device := Physical_Device.{vk_obj=device};
    if !set_physical_device_queue_family_capabilities(*dummy_device) {
        return 0;
    }
    if depth_buffer_format(device) == .UNDEFINED {
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
    if !vk_validate(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, *info.capabilities), "unable to get surface capabilities of a physical device", severity=.WARNING_MESSAGE) {
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

queue_family_index_array :: inline (physical_device: *Physical_Device) -> []u32 {
    arr: []u32 = ---;
    arr.count = 4;
    arr.data = *physical_device.present_index;
    return arr;
}

choose_swapchain_surface_format :: (info: *Swapchain_Support_Info) -> VkSurfaceFormatKHR {
    for info.formats {
        if it.format == .R8G8B8A8_UNORM && it.colorSpace == .COLOR_SPACE_SRGB_NONLINEAR_KHR {
            return it;
        }
    }
    return info.formats[0];
}

choose_swapchain_present_mode :: (info: *Swapchain_Support_Info) -> VkPresentModeKHR {
    // return .MAILBOX_KHR;
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

rendering_attachment_info :: (view: VkImageView, clear_value: *VkClearValue, layout: VkImageLayout) -> VkRenderingAttachmentInfo {
    return VkRenderingAttachmentInfo.{
        imageView=view,
        imageLayout=layout,
        loadOp = ifx clear_value != null then .CLEAR else .LOAD,
        storeOp = .STORE,
        clearValue = ifx clear_value != null then clear_value.* else .{}
    };
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
// info struct makers

image_create_info :: inline (format: VkFormat, usage_flags: VkImageUsageFlags, extent: VkExtent3D, mip_levels : u32 = 1, msaa_samples: VkSampleCountFlags = ._1_BIT /*1 = no msaa*/, tiling_format := VkImageTiling.OPTIMAL) -> VkImageCreateInfo {
    return VkImageCreateInfo.{
        imageType = ._2D,
        format = format,
        extent = extent,
        mipLevels = mip_levels,
        arrayLayers = 1,
        samples = msaa_samples,
        tiling = tiling_format,
        usage = usage_flags
    };
}

image_view_create_info :: inline (format: VkFormat, image: VkImage, aspect_flags: VkImageAspectFlags, mip_levels: u32 = 1) -> VkImageViewCreateInfo {
    return VkImageViewCreateInfo.{
        viewType = ._2D,
        image = image,
        format = format,
        subresourceRange = .{
            levelCount = mip_levels,
            layerCount = 1,
            aspectMask = aspect_flags
        }
    };
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

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// #scope_export // -------------------------------------------------------------------------------------------- { EXPORT }

immediate_submit :: () {
    cmd := immediate_command_buffer;
    if immediate_command_count > 0 {
        vk_validate(vkEndCommandBuffer(cmd), "Failed to end the immediate command buffer");
        cmd_submit_info := command_buffer_submit_info(cmd);
        submit_info := roll_submit_info(*cmd_submit_info, null, null); 
        vk_validate(vkQueueSubmit2(graphics_queue, 1, *submit_info, immediate_fence), "failed to submit immediate render commands to the graphics queue");
        vk_validate(vkWaitForFences(logical_device, 1, *immediate_fence, VK_TRUE, 99_999_999_999), "failed to wait for the immediate render fence");
        vk_validate(vkResetFences(logical_device, 1, *immediate_fence), "failed to reset the immediate render fence");
        begin_command_buffer(cmd);
        immediate_command_count = 0;
    }
}

immediate_quad :: (p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, color := Vector4.{1,1,1,1}, uv0 := Vector2.{0,0}, uv1 := Vector2.{1,0}, uv2 := Vector2.{1,1}, uv3 := Vector2.{0, 1}) {
    if program_frame == 0 then return;
    cmd := immediate_command_buffer;
    if immediate_mode == {
    case .TEXTURE;
    case .COLOR;
    case .TEXT;
        assert(false, "can't do text yet");
    }
}

// what I'm doing rn is more about learning than doing it the right way. I know that a much better way would
// be to roll a bunch of vertices/colors into a buffer then do a batched draw. to do that via compute *would*
// actually be a learning experience, but doing it via vertex/fragment wouldn't really. anyway, I'm just
// letting this be the way it is for now.
immediate_draw_rect :: (rect: Rect_Draw) {
    if program_frame == 0 then return;
    cmd := immediate_command_buffer;
    vkCmdBindPipeline(cmd, .COMPUTE, rect_pipeline);
    vkCmdBindDescriptorSets(cmd, .COMPUTE, rect_pipeline_layout, 0, 1, *draw_image_descriptors, 0, null);
    width := rect.lower_right.x - rect.upper_left.x;
    dispatch_width := ceil(width / 32.0);
    height := rect.lower_right.y - rect.upper_left.x;
    dispatch_height := ceil(height / 32.0);
    vkCmdPushConstants(cmd, rect_pipeline_layout, .COMPUTE_BIT, 0, size_of(Rect_Draw), *rect);
    vkCmdDispatch(cmd, xx dispatch_width, xx dispatch_height, 1);
    immediate_command_count += 1;
}

// TODO: mipmaps
// TDOO: explicit pixel layout? maybe only need r8 and r8g8b8a8
create_texture :: (
    img: *Texture, 
    width: s32, 
    height: s32, 
    memory: *[]u8 = null, 
    srgb := false, 
    build_mipmaps := false, 
    auto_destroy := true,
    cpu_memory_usage := enum {FREE; STBI_FREE; STORE_ON_TEXTURE; DO_NOTHING;}.STBI_FREE
) -> bool {
    bytes_per_pixel := memory.count / (width * height);
    assert(bytes_per_pixel == 1 || bytes_per_pixel == 4);
    if bytes_per_pixel == 1 {
        img.format = ifx srgb then .R8_SRGB else .R8_UNORM;
    } else {
        img.format = ifx srgb then .R8G8B8A8_SRGB else .R8G8B8A8_UNORM;
    }
    img.extent = VkExtent3D.{
        xx width,
        xx height,
        (1).(u32)
    };
    create_info := image_create_info(img.format, .SAMPLED_BIT | .TRANSFER_DST_BIT, img.extent);
    alloc_info := VmaAllocationCreateInfo.{
        usage = .GPU_ONLY,
        requiredFlags = .DEVICE_LOCAL_BIT
    };
    assert(img.extent.width > 0 && img.extent.height > 0);
    vk_validate(vmaCreateImage(vk_allocator, *create_info, *alloc_info, *img.vk_obj, *img.allocation, null), "failed to create an image for getrect");

    view_create_info := image_view_create_info(img.format, img.vk_obj, .COLOR_BIT);
    vk_validate(vkCreateImageView(logical_device, *view_create_info, null, *img.image_view), "failed to create an image view for getrect");

    if auto_destroy {
        array_add(*game_deletion_queue, .{arg1=img, proc_1arg=(img: *void){ 
            vkDestroyImageView(logical_device, img.(*Texture).image_view, null);
            vmaDestroyImage(vk_allocator, img.(*Texture).vk_obj, img.(*Texture).allocation);
        }});
    }

    if memory != null {
        assert(memory.count > 0);
        copy_cpu_memory_to_texture(img, memory.*);
    }

    if #complete cpu_memory_usage == {
    case .FREE;
        free(memory.data);
        memory.count = 0;
    case .STBI_FREE;
        stbi_image_free(memory.data);
        memory.count = 0;
    case .STORE_ON_TEXTURE;
        img.cpu_memory = memory.*;
    case .DO_NOTHING;
    }

    return true;
}

// TODO: texture destruction
// destroy_texture :: (tex: *Texture) {

// }

Rect_Draw :: struct {
    color: Vector4;
    upper_left: Vector2;
    lower_right: Vector2;
}

Immediate_Mode :: enum u8 {
    TEXTURE;
    COLOR;
    TEXT;
}

rect_draws: [..]Rect_Draw;
immediate_mode: Immediate_Mode;
immediate_texture: Texture;

// #scope_file // ------------------------------------------------------------------------------------------------ { FILE }

copy_depth_image_to_draw_image :: (cmd: VkCommandBuffer) {
    if draw_extent.width == 0 || draw_extent.height == 0 then return;

    vkCmdBindPipeline(cmd, .COMPUTE, copy_depth_image_pipeline);
    vkCmdBindDescriptorSets(cmd, .COMPUTE, copy_depth_image_pipeline_layout, 0, 1, *depth_and_draw_descriptors, 0, null);
    dispatch_width := ceil(draw_extent.width / 32.0);
    dispatch_height := ceil(draw_extent.height / 32.0);
    vkCmdDispatch(cmd, xx dispatch_width, xx dispatch_height, 1);
}

// draw_sphere :: (cmd: VkCommandBuffer, target: VkImage) {
//     if draw_extent.width == 0 || draw_extent.height == 0 then return;

//     vkCmdBindPipeline(cmd, .COMPUTE, sphere_pipeline);
//     vkCmdBindDescriptorSets(cmd, .COMPUTE, sphere_pipeline_layout, 0, 1, *draw_image_descriptors, 0, null);
//     Sphere_Constants :: struct {
//         pos_x: float;
//         pos_y: float;
//         pos_z: float;
//         radius: float;
//         norm_t: float;
//         norm_rand: float;
//     };
//     rnd := clamp(random_get(), 0, U64_MAX-256).(float) / U64_MAX.(float);
//     sphere := Sphere_Constants.{300, 300, 0, 200, sin(seconds_since_init().(float)), rnd};
//     vkCmdPushConstants(cmd, sphere_pipeline_layout, .COMPUTE_BIT, 0, size_of(float) * 6, *sphere);
//     diameter := 2.0 * sphere.radius;
//     dispatch_extent := ceil(diameter / 32.0);
//     vkCmdDispatch(cmd, xx dispatch_extent, xx dispatch_extent, 1);
// }

draw_capsules :: (cmd: VkCommandBuffer, target: VkImage, mvp_matrix: *Matrix4, vp_matrix: *Matrix4, capsule_bottom_center: Vector3) {
    // defer array_reset_keeping_memory(*capsules_to_draw);
    if draw_extent.width == 0 || draw_extent.height == 0 then return;

    vkCmdBindPipeline(cmd, .COMPUTE, capsule_pipeline);
    vkCmdBindDescriptorSets(cmd, .COMPUTE, capsule_pipeline_layout, 0, 1, *draw_image_descriptors, 0, null);

    // a lot of stuff in here needs information about the camera... 
    // but the camera is supposed to be a dynamic thing, so maybe referencing an old state.
    // preparing data for compute shaders feels messy as hell
    // cameras are simple and cheap to repeatedly store, so they can be saved with the draw requests that need them to reference at draw time.

    // for capsules_to_draw {
    //     cam_to_pos := normalize(capsule_bottom_center - camera.position);
    //     relevant_right := right_direction(*camera);
    //     radius_vec_0 := Vector4.{xyz=.{}, w=1}; 
    //     radius_vec_1 := Vector4.{xyz=relevant_right * it.radius, w=1};

    //     point_a := Vector4.{xyz=it.segment_point_a, w=1};
    //     point_b := Vector4.{xyz=it.segment_point_b, w=1};
    //     point_a_clip := mvp_matrix.* * point_a;
    //     point_b_clip := mvp_matrix.* * point_b;
    //     point_a_norm := point_a_clip / point_a_clip.w;
    //     point_b_norm := point_b_clip / point_b_clip.w;
        
    //     radius_norm: float;
    //     if camera.projection == .ORTHOGRAPHIC {
    //         radius_norm = it.radius * camera.orthographic.scale / draw_extent.width.(float);
    //     } else {
    //         radius_clip_vec_0 := mvp_matrix.* * radius_vec_0;
    //         radius_norm_vec_0 := radius_clip_vec_0 / radius_clip_vec_0.w;
    //         radius_clip_vec_1 := mvp_matrix.* * radius_vec_1;
    //         radius_norm_vec_1 := radius_clip_vec_1 / radius_clip_vec_1.w;
    //         radius_norm_vec := radius_norm_vec_0 - radius_norm_vec_1;
    //         radius_norm = length(radius_norm_vec * 0.5);
    //     }

    //     push_constants := Capsule_Draw_Push_Constants.{
    //         segment_point_a_x = respace(point_a_norm.x, .{-1, 1}, .{0, 1}, false),
    //         segment_point_a_y = respace(point_a_norm.y, .{-1, 1}, .{0, 1}, false),
    //         segment_point_a_z = respace(point_a_norm.z, .{-1, 1}, .{0, 1}, false),
    //         segment_point_b_x = respace(point_b_norm.x, .{-1, 1}, .{0, 1}, false),
    //         segment_point_b_y = respace(point_b_norm.y, .{-1, 1}, .{0, 1}, false),
    //         segment_point_b_z = respace(point_b_norm.z, .{-1, 1}, .{0, 1}, false),
    //         norm_radius = radius_norm,
    //         color_r = alter_cast(it.color.r, float, true),
    //         color_g = alter_cast(it.color.g, float, true),
    //         color_b = alter_cast(it.color.b, float, true),
    //         color_a = alter_cast(it.color.a, float, true),
    //     };
    //     screen_ul := Vector2.{min(push_constants.segment_point_a_x, push_constants.segment_point_b_x), min(push_constants.segment_point_a_y, push_constants.segment_point_b_y)} * Vector2.{draw_extent.width.(float), draw_extent.height.(float)};
    //     screen_lr := Vector2.{max(push_constants.segment_point_a_x, push_constants.segment_point_b_x), max(push_constants.segment_point_a_y, push_constants.segment_point_b_y)} * Vector2.{draw_extent.width.(float), draw_extent.height.(float)};

    //     vkCmdPushConstants(cmd, capsule_pipeline_layout, .COMPUTE_BIT, 0, size_of(Capsule_Draw_Push_Constants), *push_constants);

    //     // dispatch_width := max(ceil((screen_lr.x - screen_ul.x + 100.0 * 2) / 32.0), 1.0);
    //     // dispatch_height := max(ceil((screen_lr.y - screen_ul.y + 100.0 * 2) / 32.0), 1.0);
    //     // vkCmdDispatch(cmd, xx dispatch_width, xx dispatch_height, 1);
    //     vkCmdDispatch(cmd, 70, 70, 1);
    // }

}

draw_triangle :: (cmd: VkCommandBuffer, target: VkImage) {
    if draw_extent.width == 0 || draw_extent.height == 0 then return;

    vkCmdBindPipeline(cmd, .GRAPHICS, graphics_pipeline);
    vkCmdDraw(cmd, 3, 1, 0, 0);
}

draw_collision_mesh :: (cmd: VkCommandBuffer, entity: *Entity, vp_mat: *Matrix4) {
    if is_set(*entity.flags, .NEVER_SHOW_COLLIDER_MESH) {
        return;
    }
    shape := *entity.shape;
    albedo := entity.collision_mesh_albedo;
    if shape.type == {
    case .NONE;
    case .SPHERE;
        emesh := Mesh_Instance.{data=sphere_mesh_mid_poly, albedo=albedo};
        draw_mesh(cmd, entity, *emesh, vp_mat, true);
    case .CAPSULE;
        using shape.capsule;
        // todo: make a capsule mesh shader that actually works so this doesn't have to risk a million capsule meshes being made
        capsule_mesh := get_or_create_capsule_mesh(half_height*2.0, radius);
        emesh := Mesh_Instance.{data=capsule_mesh, albedo=albedo};
        draw_mesh(cmd, entity, *emesh, vp_mat, true);
    case .RECT;
        plane := get_or_load_mesh(MESH_PLANE);
        emesh := Mesh_Instance.{data=plane, albedo=albedo};
        draw_mesh(cmd, entity, *emesh, vp_mat, true);
    case .BOX;
        cube := get_or_load_mesh(MESH_CUBE);
        emesh := Mesh_Instance.{data=cube, albedo=albedo};
        draw_mesh(cmd, entity, *emesh, vp_mat, true);
    case .AABB;
        cube := get_or_load_mesh(MESH_CUBE);
        emesh := Mesh_Instance.{data=cube, albedo=albedo};
        draw_mesh(cmd, entity, *emesh, vp_mat, true);
    case .HALF_SPACE;
        plane := get_or_load_mesh(MESH_PLANE);
        emesh := Mesh_Instance.{data=plane, albedo=albedo};
        draw_mesh(cmd, entity, *emesh, vp_mat, true);
    }
}

draw_mesh :: (cmd: VkCommandBuffer, entity: *Entity, emesh: *Mesh_Instance, view_projection: *Matrix4, is_collision_mesh := false) {
    mesh := emesh.data;
    model := make_translation_matrix4(entity.center);
    rot := rotation_matrix(Matrix4, entity.orientation);
    model *= rot;

    if is_collision_mesh {
        scale: Matrix4 = ---;
        if #complete mesh.primitive_type == {
        case .NONE; #through;
        case .CAPSULE;
            scale = Matrix4_Identity;
        case .AABB; #through;
        case .BOX;
            box := *entity.body.shape.box;
            scale = make_scale_matrix4(.{box.half_width*2.0, box.half_length*2.0, box.half_height*2.0});
        case .SPHERE;
            sphere := *entity.body.shape.sphere;
            scale = make_scale_matrix4(.{sphere.radius, sphere.radius, sphere.radius});
        case .HALF_SPACE; #through;
        case .RECT;
            rect := *entity.body.shape.rect;
            scale = make_scale_matrix4(.{rect.half_width*2.0, 1.0, rect.half_height*2.0});
        }
        // todo: add draw request to array and draw instanced
        model *= scale;
    } else {
        local_translation := make_translation_matrix4(emesh.offset);
        local_rotation := rotation_matrix(Matrix4, emesh.orientation);
        local_scale := make_scale_matrix4(emesh.scale);

        model *= local_translation;
        model *= local_rotation;
        model *= local_scale;
    }
    
    draw_mesh(cmd, mesh, *model, *entity.orientation, view_projection, emesh.albedo, 1);
}

draw_mesh :: (cmd: VkCommandBuffer, mesh: *Mesh, model: *Matrix4, orientation: *Quaternion, view_projection: *Matrix4, albedo: Mesh_Albedo, instance_count: u32 = 1) {
    if draw_extent.width == 0 || draw_extent.height == 0 then return;

    vkCmdBindPipeline(cmd, .GRAPHICS, graphics_pipeline);
    offset : u64 = 0;
    vkCmdBindDescriptorSets(cmd, .GRAPHICS, graphics_pipeline_layout, 0, 1, *mesh_descriptors, 0, null);

    vkCmdBindVertexBuffers(cmd, 0, 1, *mesh.vbo.buffer, *offset);
    vkCmdBindIndexBuffer(cmd, mesh.ibo.buffer, 0, xx mesh.ibo.index_type);

    constants: [24]float32;
    mvp := view_projection.* * model.*;
    memcpy(constants.data, *mvp, size_of(Matrix4));
    memcpy(constants.data + 16, *albedo.tint, size_of(Vector4));
    memcpy(constants.data + 20, orientation, size_of(Quaternion));

    vkCmdPushConstants(cmd, graphics_pipeline_layout, .VERTEX_BIT, 0, size_of(float) * 24, constants.data);
    vkCmdDrawIndexed(cmd, mesh.ibo.count, instance_count, 0, 0, 0);
}

draw_lines :: (cmd: VkCommandBuffer, view_projection: *Matrix4) {
    if draw_extent.width == 0 || draw_extent.height == 0 then return;
    if lines.count == 0 then return;

    vkCmdBindPipeline(cmd, .GRAPHICS, line_pipeline);
    vkCmdSetLineWidth(cmd, 4.0);

    offset : u64 = 0;
    vkCmdBindVertexBuffers(cmd, 0, 1, *line_vbo.buffer, *offset);

    constants: [16]float32;
    memcpy(constants.data, view_projection, 16 * size_of(float));

    vkCmdPushConstants(cmd, line_pipeline_layout, .VERTEX_BIT, 0, size_of(float) * 16, constants.data);
    vkCmdDraw(cmd, xx (lines.count * 2), 1, 0, 0);
}

draw_spheres :: (cmd: VkCommandBuffer, view_projection: *Matrix4) {
    defer array_reset_keeping_memory(*sphere_draws);
    if draw_extent.width == 0 || draw_extent.height == 0 then return;

    vkCmdBindPipeline(cmd, .GRAPHICS, graphics_pipeline);
    vkCmdBindDescriptorSets(cmd, .GRAPHICS, graphics_pipeline_layout, 0, 1, *mesh_descriptors, 0, null);

    quick_sort(sphere_draws, (a,b) => a.poly_count - b.poly_count);

    group_poly_count: Sphere_Poly_Count = 0;
    group_index_count: s64;
    offset: u64 = 0;
    mesh_ptr: *Mesh;
    for sphere_draws {
        if it.poly_count != group_poly_count {
            group_poly_count = it.poly_count;
            if group_poly_count == {
            case .LOW;
                mesh_ptr = sphere_mesh_low_poly;
                vkCmdBindVertexBuffers(cmd, 0, 1, *sphere_mesh_low_poly.vbo.buffer, *offset);
                vkCmdBindIndexBuffer(cmd, sphere_mesh_low_poly.ibo.buffer, 0, xx sphere_mesh_low_poly.ibo.index_type);
                group_index_count = sphere_mesh_low_poly.ibo.count;
            case .MEDIUM;
                mesh_ptr = sphere_mesh_mid_poly;
                vkCmdBindVertexBuffers(cmd, 0, 1, *sphere_mesh_mid_poly.vbo.buffer, *offset);
                vkCmdBindIndexBuffer(cmd, sphere_mesh_mid_poly.ibo.buffer, 0, xx sphere_mesh_mid_poly.ibo.index_type);
                group_index_count = sphere_mesh_mid_poly.ibo.count;
            case .HIGH;
                mesh_ptr = sphere_mesh_high_poly;
                vkCmdBindVertexBuffers(cmd, 0, 1, *sphere_mesh_high_poly.vbo.buffer, *offset);
                vkCmdBindIndexBuffer(cmd, sphere_mesh_high_poly.ibo.buffer, 0, xx sphere_mesh_high_poly.ibo.index_type);
                group_index_count = sphere_mesh_high_poly.ibo.count;
            case;
                rm_error("invalid group poly count");
                return;
            }
        }

        model := make_translation_matrix4(it.position);
        scale := make_scale_matrix4(.{it.radius, it.radius, it.radius});
        // todo: add draw request to array and draw instanced
        model *= scale;
        quat_identity := QUATERNION_IDENTITY;
        draw_mesh(cmd, mesh_ptr, *model, *quat_identity, view_projection, Mesh_Albedo.{tint=it.color}, 1);
    }
}

prepare_lights :: () {
    // sun_t := asin(respace(sin(seconds_since_init().(float)), .{-1, 1}, .{-0.5, 0.5}));
    // down_vec := WORLD_DOWN;
    // sun_t := 0;
    // lights.sun_direction = rotate(down_vec, WORLD_FORE, sun_t);
    // lights.sun_direction = rotate(WORLD_FORE, WORLD_RIGHT, 0.5);
    // lights.sun_direction = WORLD_DOWN;
    lights.sun_direction = rotate(WORLD_DOWN, WORLD_RIGHT, 0.3);
    copy_cpu_memory_to_buffer(lights.buffer, as_string(lights.data));
}

// TODO: make it so it can have 0 cylinder sections
generate_capsule_geo :: (out_vertices: *[..]Mesh_Vertex, out_indices: *[..]u16, height: float, radius: float, triangulize_distance := 1.0) {
    cylinder_height := height - 2.0 * radius;
    assert(cylinder_height >= 0);
    assert(out_indices.data == null && out_indices.count == 0);
    assert(out_vertices.data == null && out_vertices.count == 0);

    inv_triangulize_distance := 1.0 / triangulize_distance;
    circumference := 2.0 * PI * radius;

    // the belt is the largest circle/cross section when looking down on an upright capsule. in other words, it's the circle that represents the cylinder part of the capsule in xy space. the vertex count along the belt needs to be a power of two so that by halving it, we always have exactly half with no remainder. important for sphere triangulization. this is broken up into steps as an artifact of a debugging process.
    target_belt_vertex_count_step_1 := circumference * inv_triangulize_distance;
    target_belt_vertex_count_step_2 := max(5.0, target_belt_vertex_count_step_1);
    target_belt_vertex_count_step_3 := round(target_belt_vertex_count_step_2);
    belt_vertex_count : u32 = xx ceil_to_pow2(target_belt_vertex_count_step_3);

    rot := 2.0 * PI / belt_vertex_count.(float);

    cylinder_ring_rotator: Quaternion;
    rotate(*cylinder_ring_rotator, WORLD_UP, rot);

    trace_radius_vec := WORLD_RIGHT * radius;

    cylinder_half_height := cylinder_height * 0.5;
    cylinder_row_count : u32 = xx round(ceil(cylinder_half_height * inv_triangulize_distance));

    sphere_circumference := 2.0 * PI * radius;
    quarter_sphere_circumference := sphere_circumference * 0.25;
    half_sphere_sections := round(ceil(quarter_sphere_circumference * inv_triangulize_distance));
    // the last section has a single vertex at the top. not counting that among the rings.
    half_sphere_rings := half_sphere_sections - 1;
    assert(half_sphere_rings >= 0);

    sphere_ring_radii: []float;
    sphere_ring_counts: []u16;

    // the sphere part uses aligned vertices and attempts to match the desired number of triangles to the number per row. an operation that can do both (aligned + match desired number) is to sometimes half the number of tris when moving up a row. this loop searches up the half-sphere, finds the halvings, and sums up the vertex count for preallocation.

    half_sphere_vertex_count := 1; // at least one vertex, top center (also represents bottom center w/ symmetry)
    if half_sphere_rings >= 1 {
        sphere_ring_radii = alloc_array(float, half_sphere_rings, temp);
        sphere_ring_counts = alloc_array(u16, half_sphere_rings, temp);

        current_belt_size : u32 = belt_vertex_count;
        for 0..half_sphere_rings-1 {
            norm_angular_distance := clamp(1.0 - ((it + 1).(float) / half_sphere_sections.(float)), 0, 1);
            angle := norm_angular_distance * (PI * 0.5);
            sphere_ring_radii[it] = radius * sin(angle);
            ring_circumference := sphere_ring_radii[it] * 2.0 * PI;

            ring_target_vertex_count := round(ring_circumference * inv_triangulize_distance, u32);
            assert(ring_target_vertex_count <= current_belt_size);

            half_current_belt_size := current_belt_size >> 1;

            if ring_target_vertex_count <= half_current_belt_size {
                current_belt_size = half_current_belt_size;
            }
            sphere_ring_counts[it] = xx current_belt_size;
            half_sphere_vertex_count += current_belt_size;
        }
    }

    half_cylinder_vertex_count_minus_belt := belt_vertex_count * cylinder_row_count;
    half_vertex_count_minus_belt := half_cylinder_vertex_count_minus_belt + half_sphere_vertex_count;
    total_vertex_count := belt_vertex_count + half_cylinder_vertex_count_minus_belt * 2 + half_sphere_vertex_count * 2;

    assert(total_vertex_count <= U16_MAX);
    array_resize(out_vertices, total_vertex_count);

    belt_begin              : u32 = 0;
    belt_end                : u32 = xx belt_vertex_count;

    cylinder_top_half_begin : u32 = xx belt_end;
    cylinder_top_half_end   : u32 = xx (cylinder_top_half_begin + half_cylinder_vertex_count_minus_belt);

    sphere_top_half_begin   : u32 = xx cylinder_top_half_end;
    sphere_top_half_end     : u32 = xx (sphere_top_half_begin + half_sphere_vertex_count);

    cylinder_bot_half_begin : u32 = xx sphere_top_half_end;
    cylinder_bot_half_end   : u32 = xx (cylinder_bot_half_begin + half_cylinder_vertex_count_minus_belt);

    sphere_bot_half_begin   : u32 = xx cylinder_bot_half_end;
    sphere_bot_half_end     : u32 = xx (sphere_bot_half_begin + half_sphere_vertex_count);

    assert(sphere_bot_half_end == total_vertex_count);

    // --------------------------
    // generate cylinder top half
    // --------------------------

    // triangle gen between vertex rings:
    //  0            1
    // |  \          |
    // |     \       |
    // |        \    |
    // |           \ |
    // 0             1

    for ring_pos : 0..belt_vertex_count-1 {
        // add belt vertex
        out_vertices.*[ring_pos] = .{position=trace_radius_vec};
        // add rest of vertices in cylinder (which vertically align with the belt vertices)
        for row : 1..cylinder_row_count {
            // offset from belt
            height_for_offset := min(row.(float) * triangulize_distance, cylinder_half_height);
            height_offset := WORLD_UP * height_for_offset;

            v := row * belt_vertex_count + ring_pos;
            out_vertices.*[v] = .{position=trace_radius_vec + height_offset};

            prev_ring_min : u16 = xx ((row - 1) * belt_vertex_count);
            prev_ring_max : u16 = xx (prev_ring_min + belt_vertex_count - 1);
            cur_ring_min  : u16 = xx (row * belt_vertex_count);
            cur_ring_max  : u16 = xx (cur_ring_min + belt_vertex_count - 1);

            quad_ll : u16 = xx (prev_ring_min + ring_pos);
            quad_lr : u16 = xx increment_wrap(quad_ll, prev_ring_min, prev_ring_max);
            quad_ul : u16 = xx v;
            quad_ur : u16 = xx increment_wrap(v, cur_ring_min, cur_ring_max);

            array_add(out_indices, quad_ll, quad_ul, quad_lr);
            array_add(out_indices, quad_ul, quad_ur, quad_lr);
        }
        trace_radius_vec = rotate(trace_radius_vec, cylinder_ring_rotator);
    }

    // ------------------------
    // generate sphere top half
    // ------------------------

    prev_ring_count     := belt_vertex_count;
    prev_ring_offset    := cylinder_top_half_end - belt_vertex_count;
    cur_ring_offset     := sphere_top_half_begin;

    sphere_vertex_sum := 0;
    sphere_ring_count: u32;

    for 0..half_sphere_rings-1 {
        ring_radius := sphere_ring_radii[it];
        // b = sqrt(c^2 - a^2)
        partial_half_sphere_height_for_offset := sqrt(radius * radius - ring_radius * ring_radius);
        height_for_offset := cylinder_half_height + partial_half_sphere_height_for_offset;
        ring_height_offset := WORLD_UP * height_for_offset;

        sphere_ring_count = sphere_ring_counts[it];
        ring_rot := 2.0 * PI / sphere_ring_count.(float);
        sphere_ring_rotator: Quaternion;
        rotate(*sphere_ring_rotator, WORLD_UP, ring_rot);

        trace_radius_vec = WORLD_RIGHT * ring_radius;

        for 0..sphere_ring_count-1 {
            out_vertices.*[cur_ring_offset+it] = .{position=trace_radius_vec + ring_height_offset};
            trace_radius_vec = rotate(trace_radius_vec, sphere_ring_rotator);

            if sphere_ring_count < prev_ring_count {
                // triangle gen when the current ring has half the vertex count of the previous ring (you might thing you can do less triangles by cutting out bot vertex 1 here, but this would leave holes in the mesh)
                //  0            1
                // |\           /|
                // |  \       /  |
                // |    \    /   |
                // |      \/     |
                // 0      1      2
                assert(prev_ring_count >> 1 == sphere_ring_count);

                prev_ring_min   : u16 = xx prev_ring_offset;
                prev_ring_max   : u16 = xx (prev_ring_min + prev_ring_count - 1);
                cur_ring_min    : u16 = xx cur_ring_offset;
                cur_ring_max    : u16 = xx (cur_ring_min + sphere_ring_count - 1);

                cur_ring_left   : u16 = xx (cur_ring_min + it);
                cur_ring_right  : u16 = xx increment_wrap(cur_ring_left, cur_ring_min, cur_ring_max);

                prev_ring_right := prev_ring_min + it.(u16) * 2 + 1;
                prev_ring_mid   := decrement_wrap(prev_ring_right,  prev_ring_min, prev_ring_max);
                prev_ring_left  := decrement_wrap(prev_ring_mid,    prev_ring_min, prev_ring_max);

                array_add(out_indices, cur_ring_left, cur_ring_right,   prev_ring_right);
                array_add(out_indices, cur_ring_left, prev_ring_right,  prev_ring_mid);
                array_add(out_indices, cur_ring_left, prev_ring_mid,    prev_ring_left);
            } else {
                // triangle gen when the rings have the same vertex count
                //  0            1
                // |  \          |
                // |     \       |
                // |        \    |
                // |           \ |
                // 0             1
                prev_ring_min   : u16 = xx (prev_ring_offset);
                prev_ring_max   : u16 = xx (prev_ring_min + prev_ring_count - 1);
                cur_ring_min    : u16 = xx (cur_ring_offset);
                cur_ring_max    : u16 = xx (cur_ring_min + sphere_ring_count - 1);

                prev_ring_left  : u16 = xx (prev_ring_min + it);

                quad_lower_left     : u16 = prev_ring_left;
                quad_lower_right    : u16 = increment_wrap(prev_ring_left, prev_ring_min, prev_ring_max);
                quad_upper_left     : u16 = xx (cur_ring_min + it);
                quad_upper_right    : u16 = increment_wrap((cur_ring_min + it).(u16), cur_ring_min, cur_ring_max);

                array_add(out_indices, quad_lower_left, quad_upper_left,  quad_lower_right);
                array_add(out_indices, quad_upper_left, quad_upper_right, quad_lower_right);
            }
        }

        prev_ring_count  = sphere_ring_count;
        prev_ring_offset = cur_ring_offset;

        sphere_vertex_sum += sphere_ring_count;
        cur_ring_offset   += sphere_ring_count;
    }

    // triangulize distance too high -> too low poly -> just crash
    assert(sphere_ring_count > 0);

    // final half-sphere section, connecting the top ring to the tippy-top vertex.
    out_vertices.*[cur_ring_offset] = .{position=WORLD_UP * (cylinder_half_height + radius)};
    for 0..sphere_ring_count-1 {
        final_ring_a : u16 = xx (prev_ring_offset + it);
        final_ring_b := increment_wrap(final_ring_a, xx prev_ring_offset, xx (prev_ring_offset + prev_ring_count - 1)).(u16);
        array_add(out_indices, final_ring_a, cur_ring_offset.(u16), final_ring_b);
    }

    // ------------------------------
    // mirror to make the bottom half
    // ------------------------------

    // add vertices
    for 0..half_vertex_count_minus_belt-1 {
        top_vert : u32 = xx (cylinder_top_half_begin + it);
        bot_vert : u32 = xx (cylinder_bot_half_begin + it);
        out_vertices.*[bot_vert] = out_vertices.*[top_vert];
        out_vertices.*[bot_vert].position.z *= -1.0;
    }

    // add indices
    bot_half_begin : u16 = xx cylinder_bot_half_begin;
    top_half_index_count := out_indices.count;
    top_center_vertex := bot_half_begin-1;
    bot_center_vertex := sphere_top_half_end-1;
    tri_begin : u16 = 0;

    // if the vert index is along the center belt, those indices need to be used for the first section of the bottom half. all other indices get offset to represent vertices exclusively in the bottom half of the mesh.
    maybe_offset_vert_index :: (vert_index: u16) -> u16 #expand {
        if vert_index >= `belt_vertex_count {
            return vert_index + (`half_vertex_count_minus_belt).(u16);
        }
        return vert_index;
    }

    while tri_begin < top_half_index_count {
        tri_a := maybe_offset_vert_index(out_indices.*[tri_begin+0]);
        tri_b := maybe_offset_vert_index(out_indices.*[tri_begin+1]);
        tri_c := maybe_offset_vert_index(out_indices.*[tri_begin+2]);
        array_add(out_indices, tri_c, tri_b, tri_a);
        tri_begin += 3;
    }
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// types

Queue_Family_Capability_Flags :: enum_flags {
    PRESENT;
    GRAPHICS;
    COMPUTE;
    TRANSFER;
}

Queue_Family_Indices :: struct {
    present_index: u32 = U32_MAX;
    graphics_index: u32 = U32_MAX;
    compute_index: u32 = U32_MAX;
    transfer_index: u32 = U32_MAX;
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

// #scope_export // -------------------------------------------------------------------------------------------- { EXPORT }

Texture :: struct {
    vk_obj: VkImage;   
    image_view: VkImageView;
    allocation: VmaAllocation;
    extent: VkExtent3D;
    format: VkFormat;
    cpu_memory: []u8;
}

// #scope_file // ------------------------------------------------------------------------------------------------ { FILE }

Deletion_Queue_Item :: struct {
    arg1: *void;
    arg2: *void;
    union {
        proc: ();
        proc_1arg: (*void) = ---;
        proc_2arg: (*void, *void) = ---;
    }
// #place proc_1arg;
};


Frame_Data :: struct {
    command_pool: VkCommandPool;
    command_buffer: VkCommandBuffer;
    swapchain_semaphore: VkSemaphore;
    render_semaphore: VkSemaphore;
    fence: VkFence;
    deletion_queue: [..]Deletion_Queue_Item;
}

Descriptor_Pool_Size_Ratio :: struct {
    type: VkDescriptorType;
    ratio: float32;
}

Graphics_Pipeline_Build_Info :: struct {
    shader_stages:              []VkPipelineShaderStageCreateInfo;
    input_assembly:             VkPipelineInputAssemblyStateCreateInfo;
    rasterization:              VkPipelineRasterizationStateCreateInfo;
    color_blend_attachment:     VkPipelineColorBlendAttachmentState;
    multisampling:              VkPipelineMultisampleStateCreateInfo;
    pipeline_layout:            VkPipelineLayout;
    depth_stencil:              VkPipelineDepthStencilStateCreateInfo;
    render_info:                VkPipelineRenderingCreateInfo;
    color_attachment_format:    VkFormat;
}

Shader_Hash_Item :: struct {
    hash: u64;
    shader: VkShaderModule;
}

Line_Vertex :: struct {
    position: Vector4;
    // _padding := 0.0;
    color: Color4f;
}

Mesh_Vertex :: struct {
    position: Vector3;
    uv: Vector2;
    normal: Vector3;
}


Hashed_Mesh :: struct {
    hash: u64;
    mesh: Mesh;
}

Lights :: struct {
    using #as rb: Render_Buffer;
    using data: struct {
        sun_direction: Vector3;
        padding: float;
        sun_tint: Vector4;
    }
}

Line_Data :: struct {
    a: Line_Vertex;
    b: Line_Vertex;
}

Sphere_Poly_Count :: enum u8 {
    LOW::1;
    MEDIUM;
    HIGH;
}


Sphere_Draw_Data :: struct {
    position: Vector3;
    radius: float;
    color: Color4f;
    poly_count: Sphere_Poly_Count;
}

Mesh_Albedo_Type :: enum u8 {
    TEXTURE;
    CONSTANT;
}

Mesh_Albedo :: struct {
    type: Mesh_Albedo_Type;
    tint := Color4f.{1,1,1,1};
}

Mesh_Data_Buffer_Type :: enum u8 {
    VERTEX; 
    INDEX;
}

Mesh_Index_Type :: enum u8 {
    U16 :: VkIndexType.UINT16; 
    U32 :: VkIndexType.UINT32;
}

Index_Buffer :: struct {
    type: Mesh_Index_Type;
    union {
        _u16: []u16;
        _u32: []u32 = ---;
    }
}

Mesh_Data_Buffer :: struct {
    using #as rb: Render_Buffer;
    count: u32;
    type: Mesh_Data_Buffer_Type;
    index_type: Mesh_Index_Type;
}

Mesh :: struct {
    vbo: Mesh_Data_Buffer;
    ibo: Mesh_Data_Buffer;
    primitive_type: Collision_Shape_Type = 0;
}

Render_Buffer :: struct {
    buffer: VkBuffer;
    allocation: VmaAllocation;
}


// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// methods

// TODO: srgb?
// TODO: more layouts?
vertex_descriptors :: ($T: Type, binding_index: u32 = 0) -> VkVertexInputBindingDescription, []VkVertexInputAttributeDescription {
    binding := VkVertexInputBindingDescription.{
        stride = size_of(T),
        inputRate = .VERTEX
    };

    attributes: [..]VkVertexInputAttributeDescription;
    attributes.allocator = temp;

    struct_info := cast(*Type_Info_Struct)T;
    assert(struct_info.members.count > 0);
    for *struct_info.members {
        format := vk_format(it);
        assert(format != .UNDEFINED);
        array_add(*attributes, .{
            location = xx it_index,
            binding = binding_index,
            format = format,
            offset = xx it.offset_in_bytes
        });
    }
    return binding, attributes;
}

// TODO: more formats, unorm/snorm
vk_format :: (info: *Type_Info_Struct_Member, depth := 0) -> VkFormat {
    assert(depth <= 1);
    format: VkFormat;
    if info.type.type == .FLOAT {
        format = ifx info.type.runtime_size == 4 then .R32_SFLOAT else .R64_SFLOAT;
    } else if info.type.type == .INTEGER {
        member_int_info := cast(*Type_Info_Integer)info.type;
        is_signed := member_int_info.signed;
        if info.type.runtime_size == {
        case 1;
            format = ifx is_signed then .R8_SINT else .R8_UINT;
        case 2;
            format = ifx is_signed then .R16_SINT else .R16_UINT;
        case 4;
            format = ifx is_signed then .R32_SINT else .R32_UINT;
        case 8;
            format = ifx is_signed then .R64_SINT else .R64_UINT;
        }
    } else if info.type.type == .STRUCT {
        assert(depth == 0);
        member_struct_info := cast(*Type_Info_Struct)info.type;
        assert(member_struct_info.members.count > 0);
        if member_struct_info.members.count == 1 {
            format = vk_format(info, depth + 1);
        } else {
            only_one_field_type := true;
            repeating_field_format: VkFormat;
            // look for placements
            unique_offsets: [..]s64;
            unique_offsets.allocator = temp;
            for *member_struct_info.members {
                find_success, _ := array_find(unique_offsets, it.offset_in_bytes);
                if find_success {
                    continue;
                }
                if it.flags & .CONSTANT {
                    continue;
                }
                field_format := vk_format(it, depth + 1);
                // only structs with repeating fields of same type are allowed
                if repeating_field_format == .UNDEFINED {
                    repeating_field_format = field_format;
                } else if repeating_field_format != field_format {
                    only_one_field_type = false;
                    break;
                }
                array_add(*unique_offsets, it.offset_in_bytes);
            }
            if only_one_field_type && repeating_field_format == .R32_SFLOAT {
                if unique_offsets.count == {
                case 2;
                    format = .R32G32_SFLOAT;
                case 3;
                    format = .R32G32B32_SFLOAT;
                case 4;
                    format = .R32G32B32A32_SFLOAT;
                }
            }
        }
    }
    return format;
}

// default_graphics_pipeline_build_info :: ()

deletion_queue_add :: (deletion_queue: *[..]Deletion_Queue_Item, code: $Code, $args: ..Code) #expand {
    #if args.count == 0 {
        array_add(deletion_queue, .{ proc=(){ #insert code; }});
    } else #if args.count == 1 {
        #insert -> string {
            argname := #run code_string(args[0]);
            call_str := #run code_string(code);
            return tprint("array_add(deletion_queue, .{arg1=`%, proc_1arg=(%: *void) { %; }});", argname, argname, call_str);
        }
    } else #if args.count == 2 {
        #insert -> string {
            argname1 := #run code_string(args[0]);
            argname2 := #run code_string(args[1]);
            call_str := #run code_string(code);
            return tprint("array_add(deletion_queue, .{arg1=`%, arg2=`%, proc_2arg=(%: *void, %: *void) { %; }});", argname1, argname2, argname1, argname2, call_str);
        }
    }
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

get_current_frame_data :: () -> *Frame_Data {
    return *command_frames[frame % command_frames.count.(u64)];
}

flush_deletion_queue :: (deletion_queue: [..]Deletion_Queue_Item, free_memory := false) {
    for < deletion_queue {
        if it.arg1 == null {
            it.proc();
        } else if it.arg2 == null {
            it.proc_1arg(it.arg1);
        } else {
            it.proc_2arg(it.arg1, it.arg2);
        }
    }
    if free_memory {
        array_reset(*deletion_queue);
    } else {
        array_reset_keeping_memory(*deletion_queue);
    }
}

// this is inflexible and probably not great going forward due to forcing the stages to be uniform
build_descriptor_set_layout :: (layout_builder: []VkDescriptorSetLayoutBinding, shader_stages: VkShaderStageFlags, p_next: *void = null, flags: VkDescriptorSetLayoutCreateFlags = 0) -> VkDescriptorSetLayout {
    for *layout_builder {
        it.stageFlags |= shader_stages;
    }
    info := VkDescriptorSetLayoutCreateInfo.{
        pBindings = layout_builder.data,
        bindingCount = xx layout_builder.count,
        flags = flags,
        pNext = p_next
    };

    set: VkDescriptorSetLayout;
    vk_validate(vkCreateDescriptorSetLayout(logical_device, *info, null, *set), "failed to create a descriptor set layout");
    return set;
}

// TODO: why is this the way it is
init_pool :: (pool: *VkDescriptorPool, max_sets: u32, ratios: []Descriptor_Pool_Size_Ratio) {
    sizes := temp_dynamic_array(VkDescriptorPoolSize, ratios.count);
    descriptor_count : u32 = 0;
    for ratios {
        count := (it.ratio * max_sets).(u32);
        descriptor_count += count;
        array_add(*sizes, .{type=it.type, descriptorCount=count});
    }
    vk_validate(descriptor_count <= max_sets, "too many descriptor sets: % given a max set count of %", descriptor_count, max_sets);
    info := VkDescriptorPoolCreateInfo.{
        maxSets = max_sets,
        poolSizeCount = xx sizes.count,
        pPoolSizes = sizes.data
    };
    vk_validate(vkCreateDescriptorPool(logical_device, *info, null, pool), "failed creating descriptor pool");
}

// NOTE: resetting a pool is confirmed by gpu manufacterers to be a fast path to destroy descriptor sets.
reset :: (pool: VkDescriptorPool) {
    vk_validate(vkResetDescriptorPool(logical_device, pool, 0), "failed resetting descriptor pool");
}

allocate_descriptor_set :: (pool: VkDescriptorPool, layout: VkDescriptorSetLayout) -> VkDescriptorSet {
    info := VkDescriptorSetAllocateInfo.{
        descriptorPool = pool,
        descriptorSetCount = 1,
        pSetLayouts = *layout
    };
    descriptor_set: VkDescriptorSet;
    vk_validate(vkAllocateDescriptorSets(logical_device, *info, *descriptor_set), "failed to allocate a descriptor set");
    return descriptor_set;
}

setup_mesh_data_for_flat_shading :: (in_vertices: []Mesh_Vertex, indices: []$T, out_vertices: *[..]Mesh_Vertex) {
    vertex_has_led_tri: Bit_Array(1);
    vertex_has_led_tri.items.allocator = temp;
    set_capacity(*vertex_has_led_tri, indices.count);

    assert(out_vertices.count == 0);
    array_resize(out_vertices, in_vertices.count);
    copy_array(out_vertices.*, in_vertices);

    for *(out_vertices.*) {
        it.normal = .{0,0,-1};
    }

    i := 0;
    while i < indices.count {
        index_offset := -1;
        for 0..2 {
            index := indices[i + it];
            if !bit_is_set(*vertex_has_led_tri, index) {
                index_offset = it;
                break;
            }
        }
        if index_offset == -1 {
            new_vertex := array_add(out_vertices);
            new_vertex.* = out_vertices.*[indices[i]];
            indices[i] = xx (out_vertices.count - 1);
            index_offset = 0;
        }

        // the 'provoking vertex' is the vertex that passes data through to the fragment shader when the vertex output is marked 'flat'. in this case, this fact is being leveraged to pass face normals through via specific vertices. chatgpt said that vulkan uses the last vertex as the provoking vertex, but that seems to be wrong, since I'm putting normals on the first vertex of each triangle.
        if index_offset == 1 {
            indices[i], indices[i+1], indices[i+2] = indices[i+1], indices[i+2], indices[i+0];
        } else if index_offset == 2 {
            indices[i], indices[i+1], indices[i+2] = indices[i+2], indices[i+0], indices[i+1];
        }

        face_vec1 := out_vertices.*[indices[i+1]].position - out_vertices.*[indices[i+2]].position;
        face_vec2 := out_vertices.*[indices[i+0]].position - out_vertices.*[indices[i+1]].position;
        out_vertices.*[indices[i]].normal = normalize(cross(face_vec1, face_vec2));

        set_bit(*vertex_has_led_tri, indices[i]);

        i += 3;
    }
}

// immediate_submit :: ()

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
transfer_queue: VkQueue;
// an abstraction of the drawing surface / window. unnecessary if not drawing to a window.
surface: VkSurfaceKHR;
// a series of render targets and information about them. the images that will be drawn to and presented at the same time.
swapchain: Swapchain;
command_frames: []Frame_Data;
frame: u64;

draw_image: Texture;
depth_image: Texture;

draw_extent: VkExtent2D;

draw_image_descriptors: VkDescriptorSet;
draw_image_descriptor_layout: VkDescriptorSetLayout;

depth_and_draw_descriptors: VkDescriptorSet;
depth_and_draw_descriptor_layout: VkDescriptorSetLayout;
depth_and_draw_sampler: VkSampler;

test_tex_descriptors: VkDescriptorSet;
test_tex_descriptor_layout: VkDescriptorSetLayout;
test_tex_sampler: VkSampler;

mesh_descriptors: VkDescriptorSet;
mesh_descriptor_set_layout: VkDescriptorSetLayout;

vk_allocator: VmaAllocator;

game_deletion_queue: [..]Deletion_Queue_Item;

game_descriptor_pool: VkDescriptorPool;

// eh
graphics_pipeline: VkPipeline;
graphics_pipeline_layout: VkPipelineLayout;

line_pipeline: VkPipeline;
line_pipeline_layout: VkPipelineLayout;

rect_pipeline: VkPipeline;
rect_pipeline_layout: VkPipelineLayout;

copy_depth_image_pipeline: VkPipeline;
copy_depth_image_pipeline_layout: VkPipelineLayout;

sphere_pipeline: VkPipeline;
sphere_pipeline_layout: VkPipelineLayout;

capsule_pipeline: VkPipeline;
capsule_pipeline_layout: VkPipelineLayout;

tex_pipeline: VkPipeline;
tex_pipeline_layout: VkPipelineLayout;

immediate_fence: VkFence;
immediate_command_buffer: VkCommandBuffer;
immediate_command_pool: VkCommandPool;
immediate_command_count := 0;

transfer_fence: VkFence;
transfer_command_buffer: VkCommandBuffer;
transfer_command_pool: VkCommandPool;

lines: [..]Line_Data; // $todo: rename to line_draws
line_vbo: Mesh_Data_Buffer;

shader_hash_table: [..]Shader_Hash_Item;

lights: Lights;

test_texture: Texture;

init_success := true;

clear_color := Vector4.{0,0,0,1};

cube_mesh: *Mesh;
plane_mesh: *Mesh;
sphere_mesh_low_poly: *Mesh;
sphere_mesh_mid_poly: *Mesh;
sphere_mesh_high_poly: *Mesh;

test_color_1 := Vector4.{0.35, 0.05, 0.12, 1.0};
test_color_2 := Vector4.{0.89, 0.85, 0.93, 1.0};

meshes: [..]Hashed_Mesh;

sphere_draws: [..]Sphere_Draw_Data;

cube_vertices := Mesh_Vertex.[
    .{.{-0.5,  -0.5,  -0.5}, .{0,0}, .{0,0,-1}}, // ul 0
    .{.{ 0.5,   0.5,  -0.5}, .{1,1}, .{0,0,-1}}, // lr 1
    .{.{-0.5,   0.5,  -0.5}, .{0,1}, .{0,0,-1}}, // ll 2
    .{.{ 0.5,  -0.5,  -0.5}, .{1,0}, .{0,0,-1}}, // ur 3

    .{.{-0.5,  -0.5,   0.5}, .{0,0}, .{0,0,-1}}, // ul 4
    .{.{ 0.5,   0.5,   0.5}, .{1,1}, .{0,0,-1}}, // lr 5
    .{.{-0.5,   0.5,   0.5}, .{0,1}, .{0,0,-1}}, // ll 6
    .{.{ 0.5,  -0.5,   0.5}, .{1,0}, .{0,0,-1}}, // ur 7
];

cube_indices := u16.[
    0, 1, 2, // rear 
    3, 1, 0,
    6, 5, 4, // front 
    4, 5, 7,
    2, 4, 0, // left
    6, 4, 2,
    1, 3, 7, // right
    5, 1, 7,
    3, 0, 4, // top
    7, 3, 4,
    2, 1, 6, // bottom
    1, 5, 6
];

plane_vertices := Mesh_Vertex.[
    .{.{-0.5, 0, -0.5}, .{0,0}, .{0,0,-1}},
    .{.{ 0.5, 0, -0.5}, .{0,0}, .{0,0,-1}},
    .{.{ 0.5,  0, 0.5}, .{0,0}, .{0,0,-1}},
    .{.{-0.5,  0, 0.5}, .{0,0}, .{0,0,-1}},
];

plane_indices := u16.[
    0, 1, 2,
    0, 2, 3
];

// jai compiler will null-terminate statically allocoated 'string' values and '*u8' values, but the strings in a []string don't appear to be null-terminated, thus the (*u8).[] arrays

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
    "VK_KHR_external_memory_win32", // TODO: ofc this is windows only...
    "VK_KHR_buffer_device_address",
    "VK_KHR_dynamic_rendering",
];

ONE_MILLISECOND_IN_NANSOSECONDS :: 1_000_000;
ONE_SECOND_IN_NANOSECONDS :: 1_000_000_000;
VK_API_VERSION :: VK_API_VERSION_1_3;
VK_MSAA_SAMPLES :: VkSampleCountFlagBits._1_BIT;

Load_Mesh_Type :: enum u16 {
    PRIMITIVE;
    OBJ;
}

Mesh_Load_From_File_V1 :: struct {
    version : s32 = 1;
    file: Asset_Reference;
    reorient: Quaternion;
    norm_translation_offsets: Vector3;
    flip_winding: bool;
}

Mesh_Loader_V1 :: struct {
    load_type: Load_Mesh_Type;
    primitive_type: Collision_Shape_Type;
    using data : union {
        sphere : struct {radius: float; triangulization_distance: float; } = ---;
        capsule : struct {height: float; radius: float; triangulization_distance: float; } = ---;
        from_file: Mesh_Load_From_File_V1;
    }
}

// $note: easiest way to handle using this is to just delete the contents of the mesh_loaders folder and get this to run
generate_primitive_mesh_loader_files :: () { 
    // {
    //     plane_mesh = create_mesh("_plane", plane_vertices, plane_indices);
    //     plane_mesh.primitive_type = .RECT;
    // }
    // {
    //     cube_mesh = create_mesh("_cube", cube_vertices, cube_indices);
    //     cube_mesh.primitive_type = .BOX;
    // }
    // {
    //     SPHERE_RADIUS :: 1.0;
    //     sphere_mesh_low_poly = get_or_create_capsule_mesh(SPHERE_RADIUS*2.0, SPHERE_RADIUS, 0.8);
    //     sphere_mesh_low_poly.primitive_type = .SPHERE;
    //     sphere_mesh_mid_poly = get_or_create_capsule_mesh(SPHERE_RADIUS*2.0, SPHERE_RADIUS, 0.2);
    //     sphere_mesh_mid_poly.primitive_type = .SPHERE;
    //     sphere_mesh_high_poly = get_or_create_capsule_mesh(SPHERE_RADIUS*2.0, SPHERE_RADIUS, 0.05);
    //     sphere_mesh_high_poly.primitive_type = .SPHERE;
    // }
    plane_loader: Mesh_Loader_V1;
    {
        using plane_loader;
        load_type = .PRIMITIVE;
        primitive_type = .RECT;
        success := generate_primitive_mesh_loader_file("plane", *plane_loader);
        log("generated plane asset: %", success);
    }
    cube_loader: Mesh_Loader_V1;
    {
        using cube_loader;
        load_type = .PRIMITIVE;
        primitive_type = .BOX;
        success := generate_primitive_mesh_loader_file("cube", *cube_loader);
        log("generated cube asset: %", success);
    }
}
#if BUILDVAR_GENERATE_PRIMITIVE_MESH_LOADER_FILES then #run generate_primitive_mesh_loader_files();

generate_primitive_mesh_loader_file :: (filename: string, data: *Mesh_Loader_V1) -> bool {
    scope_set_working_directory("assets/mesh_loaders/primitives");

    s: Serializer(.STATIC);
    s.memory = as_string(alloc_array(u8, 1024, temp));
    set_rw_mode(*s, .WRITE, false);

    meta_data := Asset_Meta_Data_V1.{type=.MESH, version=1};
    serialize(*s, (*meta_data).(*u8), size_of(Asset_Meta_Data_V1));
    serialize(*s, data.(*u8), size_of(Mesh_Loader_V1));

    filename_with_ext := tprint("%.mesh", filename);
    success := write_entire_file(filename_with_ext, *s);
    return success;
}