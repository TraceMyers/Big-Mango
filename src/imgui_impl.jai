
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

        memset(command_line_text_buffer.data, 0, command_line_text_buffer.count);

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

    {
        scope_set_allocator(temp);
        perf_readout_width := add_basic_perf_readout();
        command_line_height := add_command_line(perf_readout_width);
    }

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

text_size :: (text: string) -> Vector2 {
    size: Vector2;
    size.x = CalcTextSize(temp_c_string(text)).x + 2. * GetStyle().ItemSpacing.x;
    size.y = GetFrameHeight();
    return size;
}

Text_align_right :: (left_x: float, box_width: float, text: string) -> Vector2 {
    size := text_size(text);
    pos_x := left_x + box_width - size.x - GetCursorScreenPos().x;
    SetCursorPosX(pos_x);
    Text(text);
    return size;
}

Text_align_right_for_auto_resize :: (cumulative_text_size: *Vector2, text: string, text_left_offset: float) {
    print_size := Text_align_right(GetWindowPos().x + text_left_offset, GetWindowWidth(), text);
    cumulative_text_size.x = max(cumulative_text_size.x, print_size.x);
    cumulative_text_size.y += print_size.y;
}

add_basic_perf_readout :: () -> float32 {
    window_open := Begin("Performance", flags=.NoTitleBar | .NoMove | .NoResize /*| .NoBackground*/ );
    defer End();
    if !window_open then return 0.0;

    text_size: Vector2;
    left_offset := 10.0;

    Text_align_right_for_auto_resize(*text_size, tprint("Frames Per Second: %   ", FormatFloat.{value=calc_avg_fps(), trailing_width=2, width=8}), left_offset);
    Text_align_right_for_auto_resize(*text_size, tprint("Frame Time: % ms", FormatFloat.{value=calc_avg_delta_time() * 1000.0, trailing_width=2, width=8}), left_offset);
    Text_align_right_for_auto_resize(*text_size, tprint("Non-Render Time: % ms", FormatFloat.{value=non_render_dt * 1000.0, trailing_width=2, width=8}), left_offset);

    text_size.y += 6;
    window_size := GetWindowSize();
    SetWindowSize(.{text_size.x + 10, text_size.y});

    app_window_dims := get_window_dimensions();
    fixed_window_pos := Vector2.{xx app_window_dims.x - text_size.x, 4};
    SetWindowPos(*fixed_window_pos);

    return text_size.x;
}

command_line_autocomplete_callback :: (data: *InputTextCallbackData) -> s32 #c_call {
    push_context {
        // NOTE: imgui has its own doppel-buffer, so that has to used. then, imgui will copy from that buffer
        // back into ours. it has a lot of validation to make sure that's how things are handled.
        copy_best_suggestion_to_command_line_input(data.Buf, data.BufSize);
        data.BufTextLen = xx c_style_strlen(data.Buf);
        data.BufDirty = true;
        data.CursorPos = data.BufTextLen;
    }
    return 0;
}

add_command_line_input_bar :: (perf_readout_width: float32) -> input_begin_x: float32, bar_height: float32 {
    Begin("CommandLine_InputBar", flags=.NoTitleBar | /*.NoMove |*/ .NoResize | .NoBackground);
    defer End();

    is_cli_focused := IsWindowFocused();
    SetWindowPos(.{});

    line_height := GetFrameHeight() * 2 - 2;
    SetCursorPos(.{0,line_height*0.1});
    PushStyleColor(.Text, 0xff_8f_a2_8a);
    cmd_header_text := " cmd: ";
    cmd_header_text_size := text_size(cmd_header_text);
    Text(cmd_header_text);
    PopStyleColor();

    input_text_x_offset := cmd_header_text_size.x * 0.5 + 6;
    SetCursorPos(.{input_text_x_offset, 0});

    // setting the label width to zero. doing custom label
    PushItemWidth(-1);
    PushStyleVar(.WindowPadding, .{});

    if InputText("##CommandLine_InputText", command_line_text_buffer.data, command_line_text_buffer.count, .EnterReturnsTrue | .CallbackCompletion, command_line_autocomplete_callback) {
        ARGS_MAX_COUNT :: 128;
        input_str := string.{c_style_strlen(command_line_text_buffer.data), command_line_text_buffer.data};
        tokens := tokenize_and_trim(input_str, #char " ");
        if tokens.count > 0 {
            assert(tokens.count-1 <= ARGS_MAX_COUNT);
            args: [ARGS_MAX_COUNT]Command_Line_Argument;
            args_bound := bound_array(args);

            if tokens.count > 1 then for 1..tokens.count-1 {
                // todo: get types of params from the procedure struct
                arg := bound_array_add(*args_bound);
                og_str := tokens[it];
                arg._int, arg.parse_int_success = parse_int(*og_str);
                og_str = tokens[it];
                arg._float, arg.parse_float_success = parse_float(*og_str);
                arg._string = tokens[1];
            }

            rm_log("calling % from the command line", tokens[0]);
            if !try_call_command_line_procedure(tokens[0], args_bound.array) {
                rm_warning("call failure");
            }
            memset(command_line_text_buffer.data, 0, command_line_text_buffer.count);
        }
    }
    PopStyleVar();
    PopItemWidth();

    window_size: Vector2;
    app_window_dims := get_window_dimensions();
    window_size.x = xx app_window_dims.x - perf_readout_width;
    window_size.y = line_height;

    suggestion_count := add_command_line_input_suggestions(input_text_x_offset, window_size.y);

    window_size.y += suggestion_count * GetFrameHeight();
    SetWindowSize(window_size);

    if is_cli_focused {
        SetKeyboardFocusHere(0);
    }

    return input_text_x_offset, window_size.y;
}

add_command_line_input_suggestions :: (input_begin_x: float32, input_bar_height: float32) -> suggestion_count: s32 {
    input_mem := string.{c_style_strlen(command_line_text_buffer.data), command_line_text_buffer.data};
    input_tokens := tokenize_and_trim(input_mem, #char " ");
    if input_tokens.count == 0 || input_tokens[0].count == 0 {
        return 0;
    }
    is_open := BeginChild("##CommandLine_InputSuggestions"/*, flags=.NoTitleBar | .NoResize | .NoInputs | .NoNav*/);
    defer EndChild();
    if !is_open then return 0;

    SetCursorPos(.{input_begin_x-4, 0});

    out_count: s32;
    best_suggestion_index: s64 = -1;
    best_suggestion_matched_at: s64 = S64_MAX;
    for command_line_procedures {
        i := find_index_from_left(it.name, input_tokens[0], true);
        if i != -1 {
            Text(it.name);
            out_count += 1;
        }
    }

    return out_count;
}

copy_best_suggestion_to_command_line_input :: (buf: *u8, size: s64) {
    input_mem := string.{c_style_strlen(buf), buf};
    input_tokens := tokenize_and_trim(input_mem, #char " ");
    defer array_reset(*input_tokens);
    if input_tokens.count == 0 || input_tokens[0].count == 0 {
        memset(buf, 0, size);
        return;
    }
    best_suggestion_index: s64 = -1;
    best_suggestion_matched_at: s64 = S64_MAX;
    for command_line_procedures {
        i := find_index_from_left(it.name, input_tokens[0], true);
        if i != -1 && i < best_suggestion_matched_at {
            best_suggestion_matched_at = i;
            best_suggestion_index = it_index;
        }
    }

    if best_suggestion_index != -1 {
        proc_name := command_line_procedures[best_suggestion_index].name;
        assert(proc_name.count < size);
        memset(buf, 0, size);
        memcpy(buf, proc_name.data, proc_name.count);
    }
}

add_command_line :: (perf_readout_width: float32) -> float32 {
    input_begin_x, input_bar_height := add_command_line_input_bar(perf_readout_width);
    return input_bar_height;
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
command_line_text_buffer: [4096]u8;

// DestroyCursor :: (hCursor: Win32.HCURSOR) -> Win32.BOOL #foreign user32;
// win32_DestroyCursor :: DestroyCursor;

// user32 :: #system_library "user32";