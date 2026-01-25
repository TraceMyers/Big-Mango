
// ---------------------------------------------------------------------------------------------------------------------
#scope_file // ---------------------------------------------------------------------------------------------- SCOPE_FILE
// ---------------------------------------------------------------------------------------------------------------------

using ImGui;

// $todo: probably want to wrap imgui windows to generalize more desirable resize behavior
left_sidebar_width := 600.0;
resizing_left_sidebar_with_mouse_cursor: bool;

// ---------------------------------------------------------------------------------------------------------------------
#scope_export // ------------------------------------------------------------------------------------------ SCOPE_EXPORT
// ---------------------------------------------------------------------------------------------------------------------

imgui_pool: VkDescriptorPool;
imgui_context: *ImGuiContext;
command_line_text_buffer: [1024]u8;
log_filter_buffer: [256]u8;
log_paused: bool;

DEEP_DARK_BLUE :: Color4f.{0.07, 0.07, 0.25, 1.0};
DARK_GREY_BLUE :: Color4f.{0.14, 0.16, 0.3, 1.0};
PERF_HEIGHT :: 220.0;

INDENT_WIDTH :: 20.0;
scope_push_indent :: () #expand {
    Indent(INDENT_WIDTH);
    `defer Unindent(INDENT_WIDTH);
}

// todo: metaprogram or whatever
dev_ui_opacities := float.[
    0.5,
    0.62,
    0.7,
    1.0,
    1.0
];

Dev_UI_Module :: enum {
    PERF;
    LOG;
    CMD;
    LEFT_SIDEBAR;
    MENU_BAR;
}

dev_ui_enabled: Flag_Array(Dev_UI_Module);
ui_options_open: bool;


set_dev_ui_opacity :: (args: []Command_Line_Argument) {
    init_command_line_proc_or_return(args, 2);
    module, success := try_parse_command_line_arg(*args[0], Dev_UI_Module);
    if !success then return;
    value:, success = try_parse_command_line_arg(*args[1], float64);
    if !success then return;
    value = clamp(value, 0, 1);
    dev_ui_opacities[module] = xx value;
} @command_line

_imgui :: (stage: Boot_Stage) -> bool {
    if stage == .STARTUP {
        // ----------------------------------------------------------------------------------------------------- startup
        initialize_super_allocator(*test_super_allocator, context.default_allocator);
        random_seed(*test_super_allocator_random_state, 1_200_000_000);

        set(*dev_ui_enabled, .[.LEFT_SIDEBAR, .CMD]);

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

        imgui_set_theme_paper_and_ink();
        // imgui_set_theme_graphite_glass();

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

draw_dev_ui :: () {
    scope_timer();
    if quit then return;
    ImplVulkan_NewFrame();
    ImplWin32_NewFrame();
    NewFrame();
    defer Render();

    {
        scope_set_allocator(temp);
        PushStyleVar(.WindowBorderSize, 0.0);
        defer PopStyleVar();
        // menu_bar_height := add_main_menu_bar();
        if ui_options_open {
            add_ui_options_menu();
        }
        menu_bar_height := 0.0;
        app_window_dims := get_window_dimensions();
        fixed_window_size := Vector2.{600, xx app_window_dims.y};
        add_perf_graph(menu_bar_height, fixed_window_size.x);
        player := try_get_entity(*context.world.player_entity_ref);
        if !player then return;
        left_sidebar_width := add_left_sidebar(menu_bar_height);
        right_sidebar_width := add_right_sidebar(menu_bar_height);
        command_line_text_x, command_line_input_height := add_command_line(menu_bar_height, left_sidebar_width, right_sidebar_width);
    }
}

imgui_rgba :: (r: u8, g: u8, b: u8, a : u8 = 255) -> ImColor {
    return .{r.(float) / 255.0, g.(float) / 255.0, b.(float) / 255.0, a.(float) / 255.0};
}

imgui_set_theme_paper_and_ink :: () {
    s := ImGui.GetStyle();

    ROUNDING :: 4.0;
    s.WindowRounding    = ROUNDING;
    s.ChildRounding     = ROUNDING;
    s.PopupRounding     = ROUNDING;
    s.FrameRounding     = ROUNDING;
    s.ScrollbarRounding = ROUNDING;
    s.GrabRounding      = ROUNDING;
    s.TabRounding       = ROUNDING;
    s.TreeLinesRounding = ROUNDING;

    main_bg_color       := imgui_rgba(243,237,226);
    main_bg_color.xyz *= 0.85;
    secondary_bg_color  := imgui_rgba(239,232,219);
    secondary_bg_color.xyz *= 0.85;

    s.Colors[ImGui.Col.Text]                  = imgui_rgba(43,43,43);
    s.Colors[ImGui.Col.TextDisabled]          = imgui_rgba(111,106,96);
    s.Colors[ImGui.Col.WindowBg]              = main_bg_color;
    s.Colors[ImGui.Col.ChildBg]               = secondary_bg_color;
    s.Colors[ImGui.Col.PopupBg]               = secondary_bg_color;
    s.Colors[ImGui.Col.Border]                = imgui_rgba(0,0,0,35);
    s.Colors[ImGui.Col.FrameBg]               = imgui_rgba(255,255,255,180);
    s.Colors[ImGui.Col.FrameBgHovered]        = imgui_rgba(42,127,98,60);
    s.Colors[ImGui.Col.FrameBgActive]         = imgui_rgba(178,76,99,70);
    s.Colors[ImGui.Col.TitleBg]               = imgui_rgba(243,237,226);
    s.Colors[ImGui.Col.TitleBgActive]         = imgui_rgba(243,237,226);
    s.Colors[ImGui.Col.MenuBarBg]             = imgui_rgba(239,232,219);
    s.Colors[ImGui.Col.ScrollbarBg]           = imgui_rgba(239,232,219);
    s.Colors[ImGui.Col.ScrollbarGrab]         = imgui_rgba(42,127,98,120);
    s.Colors[ImGui.Col.ScrollbarGrabHovered]  = imgui_rgba(42,127,98,180);
    s.Colors[ImGui.Col.ScrollbarGrabActive]   = imgui_rgba(178,76,99,200);
    s.Colors[ImGui.Col.CheckMark]             = imgui_rgba(42,127,98);
    s.Colors[ImGui.Col.SliderGrab]            = imgui_rgba(42,127,98,220);
    s.Colors[ImGui.Col.SliderGrabActive]      = imgui_rgba(178,76,99,230);
    s.Colors[ImGui.Col.Button]                = imgui_rgba(42,127,98,230);
    s.Colors[ImGui.Col.ButtonHovered]         = imgui_rgba(42,127,98,255);
    s.Colors[ImGui.Col.ButtonActive]          = imgui_rgba(178,76,99,240);
    s.Colors[ImGui.Col.Header]                = imgui_rgba(42,127,98,80);
    s.Colors[ImGui.Col.HeaderHovered]         = imgui_rgba(178,76,99,120);
    s.Colors[ImGui.Col.HeaderActive]          = imgui_rgba(42,127,98,160);
    s.Colors[ImGui.Col.Separator]             = imgui_rgba(0,0,0,50);
    s.Colors[ImGui.Col.ResizeGrip]            = imgui_rgba(0,0,0,40);
    s.Colors[ImGui.Col.ResizeGripHovered]     = imgui_rgba(0,0,0,80);
    s.Colors[ImGui.Col.ResizeGripActive]      = imgui_rgba(0,0,0,120);
    s.Colors[ImGui.Col.Tab]                   = imgui_rgba(255,255,255,200);
    s.Colors[ImGui.Col.TabHovered]            = imgui_rgba(178,76,99,160);
    s.Colors[ImGui.Col.TabActive]             = imgui_rgba(42,127,98,160);
    s.Colors[ImGui.Col.TableHeaderBg]         = imgui_rgba(255,255,255,180);
    s.Colors[ImGui.Col.TableBorderStrong]     = imgui_rgba(0,0,0,40);
    s.Colors[ImGui.Col.TableBorderLight]      = imgui_rgba(0,0,0,20);

    font_config: ImGui.ImFontConfig;
    font_config.OversampleH = 3;
    font_config.OversampleV = 3;
    font_config.PixelSnapH = false;

    io := ImGui.GetIO();
    io.Fonts.AddFontFromFileTTF(io.Fonts, "../fonts/PkgTTC-IosevkaAile-33.2.9/IosevkaAile-Regular.ttc", 14.0, null, io.Fonts.GetGlyphRangesDefault(io.Fonts));

    io.Fonts.Build(io.Fonts);
}

imgui_set_theme_graphite_glass :: () {
    s := ImGui.GetStyle();

    ROUNDING :: 14.0;
    s.WindowRounding    = ROUNDING;
    s.ChildRounding     = ROUNDING;
    s.PopupRounding     = ROUNDING;
    s.FrameRounding     = ROUNDING;
    s.ScrollbarRounding = ROUNDING;
    s.GrabRounding      = ROUNDING;
    s.TabRounding       = ROUNDING;
    s.TreeLinesRounding = ROUNDING;

    s.Colors[ImGui.Col.Text]                  = imgui_rgba(245,245,245);
    s.Colors[ImGui.Col.TextDisabled]          = imgui_rgba(154,160,166);
    s.Colors[ImGui.Col.WindowBg]              = imgui_rgba(15,17,21,235);
    s.Colors[ImGui.Col.ChildBg]               = imgui_rgba(21,25,34,204);
    s.Colors[ImGui.Col.PopupBg]               = imgui_rgba(21,25,34,235);
    s.Colors[ImGui.Col.Border]                = imgui_rgba(138,180,248,80);
    s.Colors[ImGui.Col.FrameBg]               = imgui_rgba(21,25,34,220);
    s.Colors[ImGui.Col.FrameBgHovered]        = imgui_rgba(138,180,248,80);
    s.Colors[ImGui.Col.FrameBgActive]         = imgui_rgba(194,194,194,110);
    s.Colors[ImGui.Col.TitleBg]               = imgui_rgba(15,17,21,235);
    s.Colors[ImGui.Col.TitleBgActive]         = imgui_rgba(15,17,21,235);
    s.Colors[ImGui.Col.ScrollbarBg]           = imgui_rgba(15,17,21,200);
    s.Colors[ImGui.Col.ScrollbarGrab]         = imgui_rgba(138,180,248,110);
    s.Colors[ImGui.Col.ScrollbarGrabHovered]  = imgui_rgba(138,180,248,170);
    s.Colors[ImGui.Col.ScrollbarGrabActive]   = imgui_rgba(138,180,248,220);
    s.Colors[ImGui.Col.CheckMark]             = imgui_rgba(138,180,248);
    s.Colors[ImGui.Col.SliderGrab]            = imgui_rgba(138,180,248,220);
    s.Colors[ImGui.Col.SliderGrabActive]      = imgui_rgba(194,194,194,240);
    s.Colors[ImGui.Col.Button]                = imgui_rgba(138,180,248,220);
    s.Colors[ImGui.Col.ButtonHovered]         = imgui_rgba(194,194,194,240);
    s.Colors[ImGui.Col.ButtonActive]          = imgui_rgba(138,180,248,255);
    s.Colors[ImGui.Col.Header]                = imgui_rgba(138,180,248,90);
    s.Colors[ImGui.Col.HeaderHovered]         = imgui_rgba(194,194,194,130);
    s.Colors[ImGui.Col.HeaderActive]          = imgui_rgba(138,180,248,160);
    s.Colors[ImGui.Col.Separator]             = imgui_rgba(194,194,194,80);
    s.Colors[ImGui.Col.ResizeGrip]            = imgui_rgba(194,194,194,120);
    s.Colors[ImGui.Col.ResizeGripHovered]     = imgui_rgba(194,194,194,180);
    s.Colors[ImGui.Col.ResizeGripActive]      = imgui_rgba(194,194,194,240);
    s.Colors[ImGui.Col.Tab]                   = imgui_rgba(21,25,34,220);
    s.Colors[ImGui.Col.TabHovered]            = imgui_rgba(138,180,248,180);
    s.Colors[ImGui.Col.TabActive]             = imgui_rgba(138,180,248,140);
    s.Colors[ImGui.Col.TableHeaderBg]         = imgui_rgba(21,25,34,220);
    s.Colors[ImGui.Col.TableBorderStrong]     = imgui_rgba(194,194,194,60);
    s.Colors[ImGui.Col.TableBorderLight]      = imgui_rgba(194,194,194,30);
    // Optional: emphasize focus
    s.Colors[ImGui.Col.NavHighlight]          = imgui_rgba(138,180,248,220);

    font_config: ImGui.ImFontConfig;
    font_config.OversampleH = 3;
    font_config.OversampleV = 3;
    font_config.PixelSnapH = false;

    io := ImGui.GetIO();
    io.Fonts.AddFontFromFileTTF(io.Fonts, "../fonts/SegoeUI-VF/SegoeUI-VF.ttf", 16.0, null, io.Fonts.GetGlyphRangesDefault(io.Fonts));

    io.Fonts.Build(io.Fonts);   
}


imgui_process_event :: (event: Input.Event) {
    using io := GetIO();

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

text_size :: (text: string) -> Vector2 {
    size: Vector2;
    size.x = CalcTextSize(temp_c_string(text)).x + 2. * GetStyle().ItemSpacing.x;
    size.y = GetFrameHeight();
    return size;
}

Text_align_right :: (left_x: float, box_width: float, text: string) -> Vector2 {
    size := text_size(text);
    pos_x := left_x + box_width - size.x;
    SetCursorPosX(pos_x);
    Text(text);
    return size;
}

SeparatorText_align_right :: (left_x: float, box_width: float, text: string) -> Vector2 {
    size := text_size(text);
    pos_x := left_x + box_width - size.x;
    SetCursorPosX(pos_x - 20);
    SeparatorText(temp_c_string(text));
    return size;
}

Text_align_right_for_auto_resize :: (cumulative_text_size: *Vector2, text: string, text_left_offset: float) {
    print_size := Text_align_right(GetWindowPos().x + text_left_offset, GetWindowWidth(), text);
    cumulative_text_size.x = max(cumulative_text_size.x, print_size.x);
    cumulative_text_size.y += print_size.y;
}

add_perf_stats :: (menu_bar_height: float, parent_width: float) -> float32 {
    // window_open := BeginChild("PerformanceReadout");
    // defer EndChild();
    // if !window_open then return 0.0;
    // SetCursorPos(.{-30,0});

    text_size: Vector2;
    left_offset := 0.0;

    // PushStyleColor(.Text, .{0.79, 0.79, 0.89, 1.0});
    // defer PopStyleColor();

    if is_profiling_on {
        time_delta := seconds_since_init() - profiling_started_at_time;
        Text("profiling for % seconds", FormatFloat.{value=time_delta, zero_removal=.NO, width=4, trailing_width=1});
    }

    SameLine();

    // Text_align_right_for_auto_resize(*text_size, tprint("% | % ", input_focus, control_mode), left_offset);
    avg_fps := round(calc_avg_fps());
    Text_align_right_for_auto_resize(*text_size, tprint("frames per second:   %         ", avg_fps), left_offset);
    Text_align_right_for_auto_resize(*text_size, tprint("frame time: % ms", FormatFloat.{value=calc_avg(delta_times) * 1000.0, trailing_width=1, width=8, zero_removal=.NO}), left_offset);
    Text_align_right_for_auto_resize(*text_size, tprint("simulation time: % ms", FormatFloat.{value=simulation_dt * 1000.0, trailing_width=1, width=8, zero_removal=.NO}), left_offset);
    Text_align_right_for_auto_resize(*text_size, tprint("render time: % ms", FormatFloat.{value=render_dt * 1000.0, trailing_width=1, width=8, zero_removal=.NO}), left_offset);

    text_size.y += 6;
    window_size := GetWindowSize();
    // SetWindowSize(.{text_size.x + 10, text_size.y});
    // SetWindowPos(.{parent_width - (text_size.x + 2), 12});

    return text_size.x;
}

add_perf_graph :: (menu_bar_height: float, parent_width: float) {
    if !is_set(*dev_ui_enabled, .PERF) {
        return; 
    }

    ImGui.PushStyleColor(.Text, imgui_rgba(200, 200, 200));
    defer PopStyleColor();

    perf_opacity := dev_ui_opacities[Dev_UI_Module.PERF];
    scope_set_alpha(perf_opacity);

    window_size := ImVec2.{parent_width, PERF_HEIGHT + 4.0};
    SetNextWindowSize(window_size);
    window_pos := ImVec2.{y=menu_bar_height};
    SetNextWindowPos(window_pos);
    window_open := Begin("PerformanceGraph", null, .NoTitleBar | .NoCollapse);
    defer End();

    SetCursorPos(.{});

    draw_list := GetWindowDrawList();
    screen_pos := GetCursorScreenPos();

    graph_width := parent_width;
    graph_height := PERF_HEIGHT;
    time_scale := graph_width / xx DELTA_TIME_COUNT;
    max_frame_time := 0.001666;
    height_scale := graph_height / max_frame_time;

    ul := screen_pos;
    lr := screen_pos + .{graph_width, graph_height};
    bg_color := to_color4b(.{rgb=DEEP_DARK_BLUE.rgb, a=perf_opacity});
    draw_list.AddRectFilled(draw_list, *ul, *lr, bg_color._u32);

    whole_bar_width := graph_width / xx DELTA_TIME_COUNT;
    part_bar_width := graph_width / xx DELTA_TIME_COUNT * 0.9;
    x_offset := whole_bar_width * 0.5;

    red_frame_time := 0.016666;
    yellow_frame_time := red_frame_time * 0.5;
    green_frame_time := red_frame_time * 0.25;

    all_under_green_mark := true;
    all_under_yellow_mark := true;

    simu_color := Color4b.{0x44, 0xcc, 0xa4, xx (200.0 * perf_opacity)};
    rndr_color := Color4b.{0x3f, 0x88, 0xd5, xx (200.0 * perf_opacity)};
    sync_color := Color4b.{0xe9, 0x72, 0x4c, xx ( 70.0 * perf_opacity)};

    for 0..DELTA_TIME_COUNT-1 {
        sync_dt := delta_times[it];
        simu_dt := simulation_times[it];
        rndr_dt := render_times[it];
        sum_dt := simu_dt + rndr_dt;

        x_pos := x_offset + whole_bar_width * xx it;
        simu_height := PERF_HEIGHT * (simu_dt / red_frame_time);
        simu_top_y := lr.y - simu_height;
        rndr_height := PERF_HEIGHT * (rndr_dt / red_frame_time);
        rndr_top_y := simu_top_y - rndr_height;
        sync_height := PERF_HEIGHT * (sync_dt / red_frame_time);
        sync_top_y := min(lr.y - sync_height, graph_height-1.0);

        draw_list.AddLine(draw_list, .{x_pos, lr.y},       .{x_pos, simu_top_y}, simu_color._u32, part_bar_width);
        draw_list.AddLine(draw_list, .{x_pos, simu_top_y}, .{x_pos, rndr_top_y}, rndr_color._u32, part_bar_width);
        draw_list.AddLine(draw_list, .{x_pos, rndr_top_y}, .{x_pos, sync_top_y}, sync_color._u32, part_bar_width);

        all_under_green_mark &= sum_dt <= green_frame_time;
        all_under_yellow_mark &= sum_dt <= yellow_frame_time;
    }

    red     := Color4b.{200, 100, 100, xx (150.0 * perf_opacity)};
    yellow  := Color4b.{140, 120,  25, xx (140.0 * perf_opacity)};
    green   := Color4b.{80,  140,  82, xx (140.0 * perf_opacity)};

    green_line_thickness := 1.0;
    yellow_line_thickness := 1.0;
    red_line_thickness := 1.0;

    if all_under_green_mark {
        green.a = alter_cast(perf_opacity, u8, true);
        green_line_thickness = 1.8;
    } else if all_under_yellow_mark {
        yellow.a = alter_cast(perf_opacity, u8, true);
        yellow_line_thickness = 1.8;
    } else {
        red.a = alter_cast(perf_opacity, u8, true);
        red_line_thickness = 1.8;
    }

    // 60 fps
    draw_list.AddLine(draw_list, .{ul.x, ul.y}, .{lr.x, ul.y}, red._u32, red_line_thickness);
    // 120 fps
    draw_list.AddLine(draw_list, .{ul.x, (ul.y + lr.y)*0.5}, .{lr.x, (ul.y + lr.y)*0.5}, yellow._u32, yellow_line_thickness);
    // 240 fps
    draw_list.AddLine(draw_list, .{ul.x, (ul.y + lr.y)*0.75}, .{lr.x, (ul.y + lr.y)*0.75}, green._u32, green_line_thickness);

    add_perf_stats(menu_bar_height, parent_width);
}

add_main_menu_bar :: () -> float {
    // PushStyleColor(.MenuBarBg, .{xyz=DEEP_DARK_BLUE.vec3, w=1.0});
    // defer PopStyleColor();

    SetNextWindowPos(.{});
    SetCursorPos(.{});

    if !is_set(*dev_ui_enabled, .MENU_BAR) {
        return 0.0;
    }

    window_open := BeginMainMenuBar();
    defer EndMainMenuBar();

    if BeginMenu("ui opacities") {
        defer EndMenu();
        SliderFloat("perf", *dev_ui_opacities[Dev_UI_Module.PERF], 0, 1);
        SliderFloat("log", *dev_ui_opacities[Dev_UI_Module.LOG], 0, 1);
        SliderFloat("left bar", *dev_ui_opacities[Dev_UI_Module.LEFT_SIDEBAR], 0, 1);
        SliderFloat("command line", *dev_ui_opacities[Dev_UI_Module.CMD], 0, 1);
    }

    return GetWindowHeight();
}

add_ui_options_menu :: () {
    SetNextWindowPos(.{});

    SetNextWindowFocus();
    if Begin("ui opacities", null, .NoTitleBar | .NoResize | .NoCollapse | .AlwaysAutoResize) {
        checkbox_bool: bool;
        #insert -> string {
            builder: String_Builder;
            ui_module_type := Dev_UI_Module.(*Type_Info_Enum);
            log("ui_module_type: %", ui_module_type.*);
            for ui_module_type.names {
                print(*builder, 
#string HERE
    checkbox_bool = is_set(*dev_ui_enabled, .%);
    Checkbox("##_%", *checkbox_bool);
    if checkbox_bool {
        set(*dev_ui_enabled, .%);
    } else {
        unset(*dev_ui_enabled, .%);
    }
    SameLine();
    SliderFloat("%", *dev_ui_opacities[Dev_UI_Module.%], 0, 1);
HERE,               
                    it,
                    it,
                    it,
                    it,
                    it, it,
                );
            }
            return builder_to_string(*builder);
        }
    }
    End();
}

add_left_sidebar :: (main_menu_height: float) -> float {
    if !is_set(*dev_ui_enabled, .LEFT_SIDEBAR) {
        return 0;
    }

    // PushStyleColor(.WindowBg, .{0.1,0.1,0.1,1.0});
    // defer PopStyleColor();

    scope_set_alpha(dev_ui_opacities[Dev_UI_Module.LEFT_SIDEBAR]);
    window_open := Begin("##LeftSidebar", flags=.NoTitleBar | .NoScrollbar | .NoResize | .NoMove); 
    defer End();

    if is_set(*dev_ui_enabled, .PERF) {
        SetWindowPos(.{y=PERF_HEIGHT});
    } else {
        SetWindowPos(.{});
    }

    app_window_dims := get_window_dimensions();
    fixed_window_size := Vector2.{left_sidebar_width, xx app_window_dims.y};
    SetWindowSize(*fixed_window_size);
    window_width := GetWindowSize().x;

    if window_open {
        add_entity_controls();
        add_entity_pocket();
        add_dev_ui_scratch_space();
        add_super_allocator_test_ui_thing();
    }

    SetWindowSize(.{left_sidebar_width, GetCursorPos().y});

    mouse_position := GetMousePos();
    window_relative_mouse_position := mouse_position - GetWindowPos();
    window_size := GetWindowSize();
    mouse_position_right_x_dist := abs(window_size.x - window_relative_mouse_position.x);

    mouse_position_middle_y_dist := abs(window_size.y / 2 - window_relative_mouse_position.y);
    if mouse_position_right_x_dist < 8 && mouse_position_middle_y_dist < window_size.y / 2 {
        // $todo: show resize cursor
        if !resizing_left_sidebar_with_mouse_cursor {
            if (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_LEFT] & .DOWN) != 0 {
                resizing_left_sidebar_with_mouse_cursor = true;
            }
        }
    }
    if resizing_left_sidebar_with_mouse_cursor {
        // $todo: draw_line() for highlight
        if (Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_LEFT] & .DOWN) == 0 {
            resizing_left_sidebar_with_mouse_cursor = false;
        } else {
            left_sidebar_width = mouse_position.x;
        }
    }

    return window_width;
}

add_right_sidebar :: (menu_bar_height: float) -> float {
    if !is_set(*dev_ui_enabled, .LOG) {
        return 0;
    }

    alpha := dev_ui_opacities[Dev_UI_Module.LOG];
    scope_set_alpha(alpha);
    // PushStyleColor(.WindowBg, .{xyz=DEEP_DARK_BLUE.vec3, w=1.0});
    // defer PopStyleColor();

    window_open := Begin("##RightSidebar", flags=.NoTitleBar | .NoScrollbar | .NoResize | .NoMove); 
    defer End();

    WIDTH :: 600.0;
    app_window_dims := get_window_dimensions();

    SetWindowPos(.{xx app_window_dims.x - WIDTH, menu_bar_height});
    SetWindowSize(.{WIDTH, xx app_window_dims.y});
    SetCursorPos(.{6, 6});
    window_width := GetWindowSize().x;

    if window_open {
        add_log_filter(window_width);
        add_log(window_width);
    }

    return window_width;
}

// NOTE: this function is quite expensive. should be easy to cull the text, then it won't be expensive.
add_log :: (parent_width: float) {
    app_window_dims := get_window_dimensions();
    child_size := Vector2.{parent_width, xx app_window_dims.y - GetCursorPosY()};
    window_open := BeginChild("##Log", *child_size, window_flags=.NoScrollbar); 
    defer /*if window_open then*/ EndChild();

    alpha := dev_ui_opacities[Dev_UI_Module.LOG];
    // PushStyleColor(.ChildBg, .{0.07, 0.07, 0.25, alpha});
    // defer PopStyleColor();

    filter := string.{c_style_strlen(log_filter_buffer.data), log_filter_buffer.data};

    // PushStyleColor(.Text, .{0.6, 0.6, 0.6, alpha});
    // defer PopStyleColor();

    i := decrement_wrap(rm_log_message_top, 0, xx (rm_log_messages.count-1));
    while i != rm_log_message_top {
        log_message, repeat_count := get_rm_log_message(i);
        i = decrement_wrap(i, 0, xx (rm_log_messages.count-1));
        if filter.count > 0 {
            if find_index_from_left(log_message, filter, true, true) == -1 {
                continue;
            }
        }
        STARTUP_HEADER :: "[STARTUP]";
        WARNING_HEADER :: "[WARNING]";
        ERROR_HEADER :: "[ERROR]";
        LOG_HEADER :: "[LOG]";
        pushed_style := false;
        if begins_with(log_message, STARTUP_HEADER) {
            // PushStyleColor(.Text, .{0.4, 0.85, 0.72, alpha});
            pushed_style = true;
        } else if begins_with(log_message, WARNING_HEADER) {
            // PushStyleColor(.Text, .{0.82, 0.85, 0.4, alpha});
            pushed_style = true;
        } else if begins_with(log_message, ERROR_HEADER) {
            // PushStyleColor(.Text, .{0.92, 0.65, 0.59, alpha});
            pushed_style = true;
        } else if begins_with(log_message, LOG_HEADER) {
            // PushStyleColor(.Text, .{0.6, 0.84, 0.88, alpha});
            pushed_style = true;
        }
        cursor_pos := GetCursorPos();
        PushTextWrapPos(GetCursorPosX() + (parent_width - 30.0));
        TextWrapped(log_message);
        PopTextWrapPos();
        if repeat_count > 1 {
            SameLine();
            Text_align_right(0, parent_width, tprint("%", repeat_count));
        }
        // if pushed_style {
        //     PopStyleColor();
        // }
    }
}

log_filter_callback :: (data: *InputTextCallbackData) -> s32 #c_call {
    ACCEPT : s32 : 0;
    REJECT : s32 : 1;
    push_context {
        // reject char that brings up command line
        if data.EventChar == #char "`" {
            return REJECT;
        }

    }
    return ACCEPT;
}

add_log_filter :: (parent_width: float) {
    // PushStyleColor(.Text, Vector4.{0.8, 0.8, 0.8, 1.0});
    // defer PopStyleColor();
    InputText("filter##log_filter", log_filter_buffer.data, xx log_filter_buffer.count, .CallbackCharFilter, log_filter_callback);
    if IsItemClicked() {
        set_input_focus(.LOG_FILTER);
    }
    SameLine();
    Checkbox("pause", *log_paused);
}

add_debug_window_spawner :: () {
    // if CollapsingHeader("debug windows##debug_windows") {
    //     Text("hey");
    // }
}

add_player_character_readout :: () {
    if CollapsingHeader("player character") {

    }
}

add_camera_controls :: () {
    if CollapsingHeader("camera") {
        SliderFloat("free fly move speed", *free_fly_linear_speed, 0.0, 1000.0);
        SliderFloat("free fly look speed", *free_fly_mouse_look_speed, 0.0, 1.0);
        SliderFloat("ortho scale", *ortho_scale, 0.01, 100.0);
    }
}

add_physics_debugger :: () {
    /*
    using physics_debug_global_data;

    if CollapsingHeader("physics debugger") {
        #if RUN_PHYSICS_DEBUGGER {
            scope_push_indent();

            if !physics_debugger_pause {
                Text("haven't encountered a break");
                return;
            }

            if Button("step") {
                physics_debugger_step = true;
            }

            struct_formatted :: (a: $T) -> string #expand {
                return tprint("%", FormatStruct.{value=a, draw_type_name=true, use_long_form_if_more_than_this_many_members=1, use_newlines_if_long_form=true});
            }

            entity: Entity;
            if collision_entity_index != 0 {
                get_entity_at(*entity, collision_entity_index);
            }
            Text("entity:           %", entity.name);
            Text("entity index:     %", collision_entity_index);
            Text("resolve step:     %", inner_index_1);
            Text("remaining time:   %", remaining_time);

            prev_contacted_entity: Entity;
            if prev_contacted_entity_index != -1 {
                get_entity_at(*prev_contacted_entity, prev_contacted_entity_index);
            }
            Text("contacted entity: %", prev_contacted_entity.name);

            phys := ifx e_phys != null then e_phys.* else Entity_Physics_Core.{};
            props := ifx e_props != null then e_props.* else Physics_Properties.{};
            if CollapsingHeader("entity phys") {
                scope_push_indent();
                TextWrapped("entity phys:      %", struct_formatted(phys));
            }
            if CollapsingHeader("entity props") {
                scope_push_indent();
                TextWrapped("entity props:     %", struct_formatted(props));
            }

            phys_2 := ifx closest_phys_b != null then closest_phys_b.* else Entity_Physics_Core.{};
            props_2 := ifx closest_props_b != null then closest_props_b.* else Physics_Properties.{};
            if CollapsingHeader("contacted entity phys") {
                scope_push_indent();
                TextWrapped(struct_formatted(phys_2));
            }
            if CollapsingHeader("contacted entity props") {
                scope_push_indent();
                TextWrapped(struct_formatted(props_2));
            } 

            if CollapsingHeader("result") {
                scope_push_indent();
                TextWrapped(struct_formatted(closest_collision_result));     
            }

            if CollapsingHeader("intermediate data") {
                scope_push_indent();
                if collision_intermediate.type != 0 {
                    TextWrapped(struct_formatted(collision_intermediate.basic));
                    if collision_intermediate.type == {
                    case .SPHERE_SPHERE;
                        TextWrapped(struct_formatted(collision_intermediate.sphere_sphere));
                        using collision_intermediate.specific.sphere_sphere;
                        draw_line(collision_intermediate._pos_a_begin, collision_intermediate._pos_a_end, .{r=1});
                        draw_line(collision_intermediate._pos_b, collision_intermediate._pos_b + WORLD_UP * 2.0, .{r=0.8,b=0.8});
                        draw_line(_point_on_segment, _point_on_segment + WORLD_UP * 2.0, .{g=1});
                        draw_line(_point_on_line, _point_on_line + WORLD_UP * 2.0, .{b=1});
                    case .SPHERE_PLANE;
                        TextWrapped(struct_formatted(collision_intermediate.sphere_plane));
                        using collision_intermediate.specific.sphere_plane;
                        draw_line(_a_closest_point, _b_closest_point, .{r=1});
                    }
                }
            }

            if CollapsingHeader("collision solution data") {
                scope_push_indent();
                using collision_intermediate.solve;
                Text("bounciness: %", _bounciness);
                if type == .ONE_WAY {
                    TextWrapped("one way: %", struct_formatted(one_way));
                } else {
                    TextWrapped("two way %", struct_formatted(two_way));
                }
            }
        } else {
            Text("physics debugger is compiled out. set RUN_PHYSICS_DEBUGGER to true.");
        }
    }
    */
}

scope_set_alpha :: (alpha: float) #expand {
    style := ImGui.GetStyle();
    save_alpha := style.Alpha;
    style.Alpha = alpha;
    `defer style.Alpha = save_alpha;
}

imgui_quaternion_input_as_euler_angles :: (text: *u8, q: *Quaternion, keyboard_switch: *bool) {
    euler_angles := to_euler_angles(q.*);
    if keyboard_switch.* {
        if InputFloat3(text, *euler_angles.component) {
            q.* = to_quaternion(euler_angles);
        }
    } else {
        if SliderFloat3(text, *euler_angles.component, -180., 180.) {
            q.* = to_quaternion(euler_angles);
        }
    }
    SameLine();
    keyboard_text := temp_c_string(tprint("keyboard##%", text));
    Checkbox(keyboard_text, keyboard_switch);
}

imgui_scale_input :: (text: *u8, scale: *Vector3, slider_min: float, slider_max: float, keyboard_switch: *bool) {
    if keyboard_switch.* {
        InputFloat3(text, *scale.component);
    } else {
        SliderFloat3(text, *scale.component, slider_min, slider_max);
    }
    SameLine();
    keyboard_text := temp_c_string(tprint("keyboard##%", text));
    Checkbox(keyboard_text, keyboard_switch);
}

imgui_button :: (text: string) -> bool {
    s := ImGui.GetStyle();
    save_color := s.Colors[ImGui.Col.Text];
    s.Colors[ImGui.Col.Text] = imgui_rgba(230,250,200);
    button_pressed := Button(text.data);
    s.Colors[ImGui.Col.Text] = save_color;
    return button_pressed;
}

add_entity_controls :: () {
    center_dummy: Vector3;
    orientation_dummy: Quaternion;

    center := *center_dummy;
    orientation := *orientation_dummy;
    meshes: []Mesh_Instance;
    name := "---";

    selected_entity := try_get_entity(*build_mode_data.selected_entity_ref);
    next_selected_entity_ref := build_mode_data.selected_entity_ref;
    
    if selected_entity != null {
        center = *selected_entity.center;
        orientation = *selected_entity.orientation;
        if selected_entity.meshes.count > 0 {
            meshes = selected_entity.meshes;
        }
        name = selected_entity.name;
    }
    
    Text_align_right(GetWindowPos().x, GetWindowWidth(), name);
    SameLine();
    SetCursorPosX(8);
    if imgui_button("duplicate") && selected_entity != null {
        duplicated_entity := duplicate_entity(selected_entity);
        next_selected_entity_ref = duplicated_entity.ref;
    }
    defer build_mode_data.selected_entity_ref = next_selected_entity_ref;

    SeparatorText("transform");

    InputFloat3("center", *center.component);

    imgui_quaternion_input_as_euler_angles("orientation", orientation, *build_mode_data.orientation_takes_keyboard_input);
    if selected_entity != null {
        set_orientation(selected_entity, orientation.*);
    }

    // inserts code and pads out to 3 lines (can either pass in 1 or 2 for 'widget_lines')
    // maybe this is dumb, but it captures the height of the passed-in widget lines and uses it to make sure the lines are all the same height. there's probably a better way.
    add_empty_lines_after_widget :: ($widget_code: string, widget_lines: s64) #expand {
        assert(widget_lines == 1 || widget_lines == 2);
        begin_y := GetCursorPos().y;
        #insert widget_code;
        new_y := GetCursorPos().y;
        multiplier := 2.0;
        if widget_lines == 2 {
            multiplier = 0.5;
        }
        y_diff := (new_y - begin_y) * multiplier;
        SetCursorPosY(new_y + y_diff);
    }

    if selected_entity != null {
        if is_set(*selected_entity.flags, .IS_PRIMITIVE_SHAPE) {
            if selected_entity.shape.type == {
            case .NONE;
            case .SPHERE;
                using_lowpoly := mesh_at_index_is_asset(selected_entity, 0, MESH_SPHERE_LOW_POLY);
                using_midpoly := mesh_at_index_is_asset(selected_entity, 0, MESH_SPHERE_MID_POLY);
                using_highpoly := mesh_at_index_is_asset(selected_entity, 0, MESH_SPHERE_HIGH_POLY);
                assert(using_lowpoly || using_midpoly || using_highpoly);
                using selected_entity.shape.sphere;
                add_empty_lines_after_widget("SliderFloat(\"sphere radius\", *`radius, `radius * 0.99, 1.01 * `radius);", 1);
                selected_entity.meshes[0].scale = .{radius, radius, radius};
            case .CAPSULE;
                assert(mesh_at_index_is_asset(selected_entity, 0, MESH_CAPSULE_1_6_0_5_0_5));
                using selected_entity.shape.capsule;
                // $todo: due to constraints on capsule meshes as they are, capsules can have only one controllable scalar. maybe just grey the other out. (also, later, capsule meshes will be drawn in a more flexible way)
                add_empty_lines_after_widget(
#string HERE
                    SliderFloat("capsule half height", *`half_height, 0, 4 * `half_height); 
                    SliderFloat("capsule radius", *`radius, 0, 4 * `radius);
HERE,
                    2
                );
            case .RECT;
                // assert(mesh_at_index_is_asset(selected_entity, 0, MESH_PLANE));
                using selected_entity.shape.rect;
                add_empty_lines_after_widget(
#string HERE
                    SliderFloat("rect half height", *`half_height, `half_height * 0.99, `half_height * 1.01);
                    SliderFloat("rect half width", *`half_width, `half_width * 0.99, `half_width * 1.01);
HERE,
                    2
                );
                if mesh_at_index_is_asset(selected_entity, 0, MESH_PLANE) || mesh_at_index_is_asset(selected_entity, 0, MESH_CUBE) {
                    selected_entity.meshes[0].scale = .{
                        half_width * 2.0,
                        1.0,
                        half_height * 2.0
                    };                   
                } else {
                    assert(false, "entity % has is primitive with rect collider, but invalid mesh at index 0", selected_entity.name);
                }
            case .BOX; #through;
            case .AABB;
                assert(mesh_at_index_is_asset(selected_entity, 0, MESH_CUBE));
                using selected_entity.shape.box;
                SliderFloat("box half height", *half_height, 0, 4 * half_height);
                SliderFloat("box half width", *half_width, 0, 4 * half_width);
                SliderFloat("box half length", *half_length, 0, 4 * half_length);
                selected_entity.meshes[0].scale = .{
                    half_width * 2.0,
                    half_length * 2.0,
                    half_height * 2.0
                };                   
            case .HALF_SPACE;
            }
        } else {
            SliderFloat("scale##entity_controls_2", *build_mode_data.selected_entity_scale.x, 0.0, 4.0);
        }

        // if apply_scale {
        //     build_mode_data.selected_entity_scale = VECTOR3_ONES;
        // }
    } else {
        scale: float;
        SliderFloat("scale##entity_controls_2", *scale, 0, 4);
    }

    dummy_mesh: Mesh_Instance;
    selected_mesh := *dummy_mesh;
    mesh_name: string;

    if meshes.count > 0 {
        build_mode_data.entity_transform_interface_selected_mesh = clamp(build_mode_data.entity_transform_interface_selected_mesh, (0).(s32), meshes.count.(s32) - 1);
        selected_mesh = *meshes[build_mode_data.entity_transform_interface_selected_mesh];
        mesh_asset := selected_mesh.data.(*Mesh_Asset);
        mesh_name = get_mesh_name(mesh_asset);
        scope_push_indent();
    }

    mesh_separator_text := temp_c_string("selected_mesh: ---");
    if mesh_name.data != null {
        mesh_separator_text = temp_c_string(tprint("selected mesh: %", mesh_name));
    }
    SeparatorText(mesh_separator_text);

    if imgui_button("select mesh") {
        OpenPopup("entity_meshes_list");
    }
    
    SameLine();
    if imgui_button("color##mesh") {
        build_mode_data.mesh_color_picker_on = true;
    }
    if build_mode_data.mesh_color_picker_on {
        if Begin("mesh color##mesh", *build_mode_data.mesh_color_picker_on, .NoScrollbar | .NoCollapse) {
            ColorPicker4("color##mesh", *selected_mesh.albedo.tint.component);
        } 
        End();
    }

    if BeginPopup("entity_meshes_list") {
        for meshes {
            mesh_asset := it.data.(*Mesh_Asset);
            mesh_name := get_mesh_name(mesh_asset);
            if Selectable(temp_c_string(mesh_name)) {
                build_mode_data.entity_transform_interface_selected_mesh = xx it_index;
            }
        }
        EndPopup();
    }

    InputFloat3("offset##mesh", *selected_mesh.offset.component);
    imgui_scale_input("scale##mesh", *selected_mesh.scale, 1, 300, *build_mode_data.mesh_scale_takes_keyboard_input);
    imgui_quaternion_input_as_euler_angles("orientation##mesh", *selected_mesh.orientation, *build_mode_data.mesh_orientation_takes_keyboard_input);
}

// eventually this should be the 'favorites' and 'workspace' for entities that I might want to place in the world during a given work session.
add_entity_pocket :: () {
    if context.world == null {
        Text("need a world to spawn stuff in it");
    }

    main_camera := get_world_main_camera(context.world);
    if main_camera == null {
        Text("need a main camera to spawn stuff in the world.");
        return;
    }

    spawn_location := look_origin(main_camera) + look_direction(main_camera) * 20.0;
    direction_2d := normalize(look_direction(main_camera).xy);
    direction_3d := Vector3.{xy=direction_2d};

    if CollapsingHeader("entity pocket") {
        if imgui_button("door") {
            spawn_swinging_door(spawn_location, direction_3d, .{r=0.5,g=0.5,b=0.5});
        }
        SameLine();
        if imgui_button("button") {
            spawn_button(spawn_location, direction_3d, .{r=0.8,g=0.8,b=0.8}, .{r=1});
        }
        SameLine();
        if imgui_button("wall") {
            spawn_wall(spawn_location, .{r=0.5,g=0.5,b=0.5});
        }
        SameLine();
        if imgui_button("floor") {
            spawn_floor(spawn_location, .{r=0.5,g=0.5,b=0.5});
        }
        SameLine();
        if imgui_button("ball") {
            spawn_ball(spawn_location, .{r=0.9,g=0.3,b=0.2});
        }
    }
}

add_dev_ui_scratch_space :: () {
    if CollapsingHeader("scratch") {
        scope_push_indent();
        
    }
}
// ---------------------------------------------------------------------------------------------------------------------
// super allocator test 
// ---------------------------------------------------------------------------------------------------------------------
#scope_file // ---------------------------------------------------------------------------------------------- SCOPE_FILE
// ---------------------------------------------------------------------------------------------------------------------

MIN_CHUNK_SZ :: 32;
test_super_allocator: Super_Allocator(MIN_CHUNK_SZ);

Test_Super_Allocator_Data :: struct {
    request_size: s32;
    bin_count: s32;
    ptr_valid: bool;
    largest_gap_per_list: string;
    gap_list_of_lists: []string;
    flag_list_of_lists: []string;
}

Test_Super_Allocator_Allocation :: struct {
    data: *u8;
    request_size: s64;
    bin_count: s64;
}

test_super_allocator_data_history: [3]Test_Super_Allocator_Data;
test_super_allocator_index: s64;
test_super_allocator_random_state: Random_State;
test_super_allocator_allocations: [..]Test_Super_Allocator_Allocation;

add_super_allocator_test_ui_thing :: () {
    scope_set_allocator(context.default_allocator);
    if CollapsingHeader("super allocator test ui thing") {
        scope_push_indent();

        did_allocator_action: bool;
        some_number: s32;
        another_number: float32;
        some_vec: Vector3;

        request_size: s64;
        bin_count: s64;
        ptr_valid: bool;

        if Button("allocate") {
            bin_ct := random_get_within_range(*test_super_allocator_random_state, 1, 72).(s64);
            alloc_sz := bin_ct * test_super_allocator.MIN_ALLOCATION_SIZE;
            ptr: *u8;
            {
                scope_set_allocator(test_super_allocator);
                ptr = alloc(alloc_sz);
            }
            array_add(*test_super_allocator_allocations, .{ptr, alloc_sz, bin_ct});
            did_allocator_action = true;
            request_size = alloc_sz;
            bin_count = bin_ct;
            ptr_valid = ptr != null;
        } 
        if Button("free last") {
            if test_super_allocator_allocations.count > 0 {
                remove_index := test_super_allocator_allocations.count - 1;
                request_size = test_super_allocator_allocations[remove_index].request_size;
                bin_count = test_super_allocator_allocations[remove_index].bin_count;
                ptr_valid = true;
                {
                    scope_set_allocator(test_super_allocator);
                    free(test_super_allocator_allocations[remove_index].data);
                }
                array_ordered_remove_by_index(*test_super_allocator_allocations, remove_index);
            }
            did_allocator_action = true;
        }
        if Button("free random") {
            if test_super_allocator_allocations.count > 0 {
                rand_val := random_get_zero_to_one();
                remove_index := round(rand_val * (test_super_allocator_allocations.count-1));
                request_size = test_super_allocator_allocations[remove_index].request_size;
                bin_count = test_super_allocator_allocations[remove_index].bin_count;
                ptr_valid = true;
                {
                    scope_set_allocator(test_super_allocator);
                    free(test_super_allocator_allocations[remove_index].data);
                }
                array_ordered_remove_by_index(*test_super_allocator_allocations, remove_index);
            }
            did_allocator_action = true;
        }

        if did_allocator_action {
            list_count := test_super_allocator.chunk_lists.count;
            {
                using *test_super_allocator_data_history[test_super_allocator_index];
                builder: String_Builder;
                for 0..list_count-1 {
                    print(*builder, "% ", FormatInt.{value=test_super_allocator.books.largest_gap_per_list[it], base=10, minimum_digits=2});
                }
                largest_gap_per_list = builder_to_string(*builder);

                gap_list_of_lists = array_alloc(string, list_count,, context.default_allocator);
                for 0..list_count-1 {
                    list_length := test_super_allocator.chunk_lists[it].count;
                    for gap_list : test_super_allocator.books.gap_list_of_lists {
                        for 0..list_length-1 {
                            print(*builder, "% ", FormatInt.{value=gap_list[it], base=10, minimum_digits=2});
                        }
                    }
                    gap_list_of_lists[it] = builder_to_string(*builder);
                }

                flag_list_of_lists = array_alloc(string, list_count,, context.default_allocator);
                for 0..list_count-1 {
                    list_length := test_super_allocator.chunk_lists[it].count;
                    for flag_list : test_super_allocator.books.flag_list_of_lists {
                        for 0..list_length-1 {
                            print(*builder, "%     ", FormatInt.{value=flag_list[it], base=2, minimum_digits=64, digits_per_comma=8, comma_string="-"});
                        }
                    }
                    flag_list_of_lists[it] = builder_to_string(*builder);
                }
            }
            test_super_allocator_index = increment_wrap(test_super_allocator_index, 0, test_super_allocator_data_history.count-1);
        }

        i := test_super_allocator_index;
        for 0..test_super_allocator_data_history.count-1 {
            i = decrement_wrap(i, 0, test_super_allocator_data_history.count-1);
            history_item := *test_super_allocator_data_history[i];
            Text("%", FormatStruct.{
                value=history_item, 
                use_long_form_if_more_than_this_many_members=1,
                use_newlines_if_long_form=true
            });
        }
    }
}
// ---------------------------------------------------------------------------------------------------------------------

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// command line procs


// ---------------------------------------------------------------------------------------------------------------------
#scope_file // ---------------------------------------------------------------------------------------------- SCOPE_FILE
// ---------------------------------------------------------------------------------------------------------------------

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

#load "command_line.jai";
