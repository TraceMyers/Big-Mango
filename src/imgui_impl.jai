
boot_imgui :: (stage: Boot_Stage) -> bool {
    if stage == .STARTUP {
        // ----------------------------------------------------------------------------------------------------- startup
        pool_sizes := VkDescriptorPoolSize.[
            .{.SAMPLER,                   1000},
            .{.COMBINED_IMAGE_SAMPLER,    1000},
            .{.SAMPLED_IMAGE,             1000},
            .{.STORAGE_IMAGE,             1000},
            .{.UNIFORM_TEXEL_BUFFER,      1000},
            .{.STORAGE_TEXEL_BUFFER,      1000},
            .{.UNIFORM_BUFFER,            1000},
            .{.STORAGE_BUFFER,            1000},
            .{.UNIFORM_BUFFER_DYNAMIC,    1000},
            .{.STORAGE_BUFFER_DYNAMIC,    1000},
            .{.INPUT_ATTACHMENT,          1000}
        ];

        pool_info := VkDescriptorPoolCreateInfo.{
            flags = .FREE_DESCRIPTOR_SET_BIT,
            maxSets = 1000,
            poolSizeCount = xx pool_sizes.count,
            pPoolSizes = pool_sizes.data
        };

        assert(vkCreateDescriptorPool(logical_device, *pool_info, null, *imgui_pool) == .SUCCESS, "failed to create the descriptor pool for imgui");

        imgui_context = CreateContext();

        // StyleColorsDark();
        StyleColorsClassic();

        assert(ImplWin32_Init(window), "failed to initialize imgui win32 implementation");

        init_info := ImplVulkan_InitInfo.{
            ApiVersion = VK_API_VERSION,
            Instance = vk_instance,  
            PhysicalDevice = physical_device.vk_obj,
            Device = logical_device,
            Queue = graphics_queue,
            DescriptorPool = imgui_pool,
            MinImageCount = 3,
            ImageCount = 3,
            UseDynamicRendering = true,
            PipelineRenderingCreateInfo = .{
                colorAttachmentCount=1,
                pColorAttachmentFormats = *swapchain.format.format
            },
            MSAASamples=VK_MSAA_SAMPLES
        };

        assert(ImplVulkan_Init(*init_info), "failed to initialize imgui vulkan implementation");
        assert(ImplVulkan_CreateFontsTexture(), "failed to create the fonts texture for imgui-vulkan");

        deletion_queue_add(*game_deletion_queue, vkDestroyDescriptorPool(logical_device, imgui_pool, null));
    } else {
        // ---------------------------------------------------------------------------------------------------- shutdown
        vkDeviceWaitIdle(logical_device);
        ImplVulkan_Shutdown();
        ImplWin32_Shutdown();
        DestroyContext(imgui_context);
    }
    return true;

}

imgui_draw :: () {
    ImplVulkan_NewFrame();
    ImplWin32_NewFrame();
    NewFrame();

    // _v: bool;
    // ShowDemoWindow(*_v);
    show_perf_readout();

    Render();
}

imgui_process_event :: (event: Input.Event) {
    using io := ImGui.GetIO();

    mouse_button: s32 = -1;
    if event.key_code == {
    case .MOUSE_BUTTON_LEFT;
        mouse_button = 0;
    case .MOUSE_BUTTON_RIGHT;
        mouse_button = 1;
    case .MOUSE_BUTTON_MIDDLE;
        mouse_button = 2;
    }
    if mouse_button != -1 {
        AddMouseButtonEvent(io, 0, event.key_pressed != 0);
        return;
    }

    if event.type == {
    case .KEYBOARD;
        imgui_update_key_modifiers(io, *event);
        imgui_key := input_key_to_imgui_key(io, event.key_code);
        AddKeyEvent(io, imgui_key, event.key_pressed != 0);
    case .TEXT_INPUT;
        AddInputCharacter(io, event.utf32);
    case .MOUSE_WHEEL;
        wheel_val := event.wheel_delta.(float) / event.typical_wheel_delta.(float);
        AddMouseWheelEvent(io, 0, wheel_val);
    }
}

#scope_file // -------------------------s--------------------------------------------------------------------- { FILE }
using ImGui;

show_perf_readout :: () {
    Begin("Performance");
    defer End();

    Text(tprint("FPS: %", FormatFloat.{value=calc_avg_fps(), trailing_width=2}));
    Text(tprint("Frame Time: % ms", FormatFloat.{value=calc_avg_delta_time() * 1000.0, trailing_width=2}));

    InputFloat3("sun direction", *lights.sun_direction.component);
    ColorPicker3("sun tint", xx *lights.sun_tint.component);

    _ffmt :: (val: float) -> FormatFloat #expand {
        return FormatFloat.{value=val, width=8, trailing_width=4};
    }

    InputFloat3("camera position", *camera.position.component);
    cam_f := fore_direction(*camera);
    Text("camera forward: <% % %>", _ffmt(cam_f.x), _ffmt(cam_f.y), _ffmt(cam_f.z));
    cam_u := up_direction(*camera);
    Text("camera up     : <% % %>", _ffmt(cam_u.x), _ffmt(cam_u.y), _ffmt(cam_u.z));
    cam_r := right_direction(*camera);
    Text("camera right  : <% % %>", _ffmt(cam_r.x), _ffmt(cam_r.y), _ffmt(cam_r.z));


    viewport := Vector2.{xx draw_image.extent.width, xx draw_image.extent.height};
    vp_mat := view_projection_matrix(*camera, viewport);
    model := Matrix4_Identity;
    // mvp := vp_mat * model;
    mvp := vp_mat;

    Text("mvp");

    Text("% % % %", _ffmt(mvp._11), _ffmt(mvp._12), _ffmt(mvp._13), _ffmt(mvp._14));
    Text("% % % %", _ffmt(mvp._21), _ffmt(mvp._22), _ffmt(mvp._23), _ffmt(mvp._24));
    Text("% % % %", _ffmt(mvp._31), _ffmt(mvp._32), _ffmt(mvp._33), _ffmt(mvp._34));
    Text("% % % %", _ffmt(mvp._41), _ffmt(mvp._42), _ffmt(mvp._43), _ffmt(mvp._44));

    // Text("face normals");
    // {
    //     i := 0;
    //     while i < test_indices.count {
    //         provoking_vertex := test_vertices[test_indices[i]];
    //         Text("<% % %>", _ffmt(provoking_vertex.normal.x), _ffmt(provoking_vertex.normal.y), _ffmt(provoking_vertex.normal.z));
    //         i += 3;
    //     }
    // }

    mouse_x, mouse_y, success := get_mouse_pointer_position(window, false);
    Text("mouse x: %", mouse_x);
    Text("mouse y: %", mouse_y);
}

imgui_update_key_modifiers :: (using io: *IO, event: *Input.Event) {
    AddKeyEvent(io, .Mod_Ctrl,  event.ctrl_pressed);
    AddKeyEvent(io, .Mod_Shift, event.shift_pressed);
    AddKeyEvent(io, .Mod_Alt,   event.alt_pressed);
    AddKeyEvent(io, .Mod_Super, event.cmd_meta_pressed);
}

input_key_to_imgui_key :: (using io: *IO, key_code: Input.Key_Code) -> Key {
    if key_code >= #char "A" && key_code <= #char "Z" {
        letter_diff := key_code.(s32) - #char "A";
        return xx (Key.A.(s32) + letter_diff);
    }
    if key_code >= #char "0" && key_code <= #char "9" {
        number_diff := key_code.(s32) - #char "0";
        return xx (Key._0.(s32) + number_diff);
    }
    if key_code >= .F1 && key_code <= .F24 {
        fkey_diff := key_code.(s32) - Input.Key_Code.F1.(s32);
        return xx (Key.F1.(s32) + fkey_diff);
    }
    if key_code == {
    case .UNKNOWN; 
        return .None;
    case .BACKSPACE;
        return .Backspace;
    case .TAB;
        return .Tab;
    case .LINEFEED;
        return .None;
    case .ENTER;
        return .Enter;
    case .ESCAPE;
        return .Escape;
    case .SPACEBAR;
        return .Space;
    // The letters A-Z live in here as well and may be returned
    // by keyboard events.
    case .DELETE;
        return .Delete;
    case .ARROW_UP;
        return .UpArrow;
    case .ARROW_DOWN;
        return .DownArrow;
    case .ARROW_LEFT;
        return .LeftArrow;
    case .ARROW_RIGHT;
        return .RightArrow;
    case .PAGE_UP;
        return .PageUp;
    case .PAGE_DOWN;
        return .PageDown;
    case .HOME;
        return .Home;
    case .END;
        return .End;
    case .INSERT;
        return .Insert;
    case .PAUSE;
        return .Pause;
    case .SCROLL_LOCK;
        return .ScrollLock;
    case .ALT;
        return .LeftAlt; 
    case .CTRL;
        return .LeftCtrl;
    case .SHIFT;
        return .LeftShift;
    case .CMD; // case .META;
        return .LeftSuper;
    case .PRINT_SCREEN;
        return .PrintScreen;
    case .MOUSE_BUTTON_LEFT;
        return .MouseLeft;
    case .MOUSE_BUTTON_MIDDLE;
        return .MouseMiddle;
    case .MOUSE_BUTTON_RIGHT;
        return .MouseRight;
    // case .MOUSE_WHEEL_UP;
    //     return .MouseWheelY;
    // case .MOUSE_WHEEL_DOWN;
    //     return .MouseWheelX;
    }
    // TODO:
    // from:
    // case .GAMEPAD_0_BEGIN;
    // case .GAMEPAD_0_END :: GAMEPAD_0_BEGIN + xx GAMEPAD_BUTTON_COUNT;
    // case .GAMEPAD_1_BEGIN;
    // case .GAMEPAD_1_END :: GAMEPAD_1_BEGIN + xx GAMEPAD_BUTTON_COUNT;
    // case .GAMEPAD_2_BEGIN;
    // case .GAMEPAD_2_END :: GAMEPAD_2_BEGIN + xx GAMEPAD_BUTTON_COUNT;
    // case .GAMEPAD_3_BEGIN;
    // case .GAMEPAD_3_END :: GAMEPAD_3_BEGIN + xx GAMEPAD_BUTTON_COUNT;
    // to:
    // GamepadStart        :: 632;
    // GamepadBack         :: 633;
    // GamepadFaceLeft     :: 634;
    // GamepadFaceRight    :: 635;
    // GamepadFaceUp       :: 636;
    // GamepadFaceDown     :: 637;
    // GamepadDpadLeft     :: 638;
    // GamepadDpadRight    :: 639;
    // GamepadDpadUp       :: 640;
    // GamepadDpadDown     :: 641;
    // GamepadL1           :: 642;
    // GamepadR1           :: 643;
    // GamepadL2           :: 644;
    // GamepadR2           :: 645;
    // GamepadL3           :: 646;
    // GamepadR3           :: 647;
    // GamepadLStickLeft   :: 648;
    // GamepadLStickRight  :: 649;
    // GamepadLStickUp     :: 650;
    // GamepadLStickDown   :: 651;
    // GamepadRStickLeft   :: 652;
    // GamepadRStickRight  :: 653;
    // GamepadRStickUp     :: 654;
    // GamepadRStickDown   :: 655;
    return .None;
}

imgui_pool: VkDescriptorPool;
imgui_context: *ImGuiContext;

// DestroyCursor :: (hCursor: Win32.HCURSOR) -> Win32.BOOL #foreign user32;
// win32_DestroyCursor :: DestroyCursor;

// user32 :: #system_library "user32";