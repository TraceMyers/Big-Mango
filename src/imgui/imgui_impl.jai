
imgui_pool: VkDescriptorPool;
imgui_context: *ImGuiContext;
command_line_text_buffer: [1024]u8;
log_filter_buffer: [256]u8;
log_paused: bool;

DEEP_DARK_BLUE :: Color4f.{0.07, 0.07, 0.25, 1.0};
DARK_GREY_BLUE :: Color4f.{0.14, 0.16, 0.3, 1.0};

INDENT_WIDTH :: 20.0;
scope_push_indent :: () #expand {
    Indent(INDENT_WIDTH);
    `defer Unindent(INDENT_WIDTH);
}

// todo: metaprogram or whatever
dev_ui_opacities := float.[
    0.4,
    0.4,
    0.4,
    0.8
];

Dev_UI_Module :: enum {
    PERF;
    LOG;
    CMD;
    LEFT_SIDEBAR;
}

set_dev_ui_opacity :: (args: []Command_Line_Argument) {
    init_command_line_proc_or_return(args, 2);
    module, success := try_parse_command_line_arg(*args[0], Dev_UI_Module);
    if !success then return;
    value:, success = try_parse_command_line_arg(*args[1], float64);
    if !success then return;
    value = clamp(value, 0, 1);
    dev_ui_opacities[module] = xx value;
} @command_line

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

draw_dev_ui :: () {
    if quit then return;
    ImplVulkan_NewFrame();
    ImplWin32_NewFrame();
    NewFrame();

    {
        scope_set_allocator(temp);
        PushStyleVar(.WindowBorderSize, 0.0);
        defer PopStyleVar();
        menu_bar_height := add_main_menu_bar();
        left_sidebar_width := add_left_sidebar(menu_bar_height);
        right_sidebar_width := add_right_sidebar(menu_bar_height);
        command_line_text_x, command_line_input_height := add_command_line(menu_bar_height, left_sidebar_width, right_sidebar_width);
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

    perf_opacity := dev_ui_opacities[Dev_UI_Module.PERF];
    alpha := min(perf_opacity * 1.3, 1);

    PushStyleColor(.Text, .{0.79, 0.79, 0.89, alpha});
    defer PopStyleColor();

    // Text_align_right_for_auto_resize(*text_size, tprint("% | % ", input_focus, control_mode), left_offset);
    Text_align_right_for_auto_resize(*text_size, tprint("frames per second: %   ", FormatFloat.{value=calc_avg_fps(), trailing_width=2, width=6, zero_removal=.NO}), left_offset);
    Text_align_right_for_auto_resize(*text_size, tprint("frame time: % ms", FormatFloat.{value=calc_avg(delta_times) * 1000.0, trailing_width=2, width=6, zero_removal=.NO}), left_offset);
    Text_align_right_for_auto_resize(*text_size, tprint("simulation time: % ms", FormatFloat.{value=simulation_dt * 1000.0, trailing_width=2, width=6, zero_removal=.NO}), left_offset);
    Text_align_right_for_auto_resize(*text_size, tprint("render time: % ms", FormatFloat.{value=render_dt * 1000.0, trailing_width=2, width=6, zero_removal=.NO}), left_offset);

    text_size.y += 6;
    window_size := GetWindowSize();
    // SetWindowSize(.{text_size.x + 10, text_size.y});
    // SetWindowPos(.{parent_width - (text_size.x + 2), 12});

    return text_size.x;
}

add_perf_graph :: (menu_bar_height: float, parent_width: float) {
    HEIGHT :: 220.0;
    window_open := BeginChild("PerformanceGraph", .{parent_width, HEIGHT + 4.0});
    defer EndChild();
    if !window_open then return;

    SetCursorPos(.{});

    draw_list := GetWindowDrawList();
    screen_pos := GetCursorScreenPos();

    graph_width := parent_width;
    graph_height := HEIGHT;
    time_scale := graph_width / xx DELTA_TIME_COUNT;
    max_frame_time := 0.001666;
    height_scale := graph_height / max_frame_time;

    perf_opacity := dev_ui_opacities[Dev_UI_Module.PERF];

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
        simu_height := HEIGHT * (simu_dt / red_frame_time);
        simu_top_y := lr.y - simu_height;
        rndr_height := HEIGHT * (rndr_dt / red_frame_time);
        rndr_top_y := simu_top_y - rndr_height;
        sync_height := HEIGHT * (sync_dt / red_frame_time);
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
    PushStyleColor(.MenuBarBg, .{xyz=DEEP_DARK_BLUE.vec3, w=1.0});
    defer PopStyleColor();

    window_open := BeginMainMenuBar();
    defer EndMainMenuBar();

    SetWindowPos(.{});
    SetCursorPos(.{});

    if BeginMenu("ui opacities") {
        defer EndMenu();
        SliderFloat("perf", *dev_ui_opacities[Dev_UI_Module.PERF], 0, 1);
        SliderFloat("log", *dev_ui_opacities[Dev_UI_Module.LOG], 0, 1);
    }

    return GetWindowHeight();
}

add_left_sidebar :: (main_menu_height: float) -> float {
    PushStyleColor(.WindowBg, .{0.1,0.1,0.1,dev_ui_opacities[Dev_UI_Module.LEFT_SIDEBAR]});
    defer PopStyleColor();
    window_open := Begin("##LeftSidebar", flags=.NoTitleBar | .NoScrollbar | .NoResize | .NoMove); 
    defer End();

    SetWindowPos(.{0, main_menu_height});
    // SetCursorPos(.{6, 6});
    app_window_dims := get_window_dimensions();
    fixed_window_size := Vector2.{600, xx app_window_dims.y};
    SetWindowSize(*fixed_window_size);
    window_width := GetWindowSize().x;

    if window_open {
        add_perf_graph(main_menu_height, fixed_window_size.x);
        add_debug_window_spawner();
        add_player_character_readout();
        add_camera_controls();
        add_physics_debugger();
        add_entity_pocket();
    }

    return window_width;
}

add_right_sidebar :: (menu_bar_height: float) -> float {
    alpha := dev_ui_opacities[Dev_UI_Module.LOG];
    PushStyleColor(.WindowBg, .{xyz=DEEP_DARK_BLUE.vec3, w=alpha});
    defer PopStyleColor();

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
    PushStyleColor(.ChildBg, .{0.07, 0.07, 0.25, alpha});
    defer PopStyleColor();

    filter := string.{c_style_strlen(log_filter_buffer.data), log_filter_buffer.data};

    PushStyleColor(.Text, .{0.6, 0.6, 0.6, alpha});
    defer PopStyleColor();

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
            PushStyleColor(.Text, .{0.4, 0.85, 0.72, alpha});
            pushed_style = true;
        } else if begins_with(log_message, WARNING_HEADER) {
            PushStyleColor(.Text, .{0.82, 0.85, 0.4, alpha});
            pushed_style = true;
        } else if begins_with(log_message, ERROR_HEADER) {
            PushStyleColor(.Text, .{0.92, 0.65, 0.59, alpha});
            pushed_style = true;
        } else if begins_with(log_message, LOG_HEADER) {
            PushStyleColor(.Text, .{0.6, 0.84, 0.88, alpha});
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
        if pushed_style {
            PopStyleColor();
        }
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
    log_alpha := dev_ui_opacities[Dev_UI_Module.LOG];
    PushStyleColor(.Text, Vector4.{0.8, 0.8, 0.8, 1.0} * log_alpha);
    defer PopStyleColor();
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
}

// eventually this should be the 'favorites' and 'workspace' for entities that I might want to place in the world during a given work session.
add_entity_pocket :: () {
    if CollapsingHeader("entity pocket") {
        if Button("capsule") {
            entity := spawn_entity(.STATIC_MESH, name="test", physics_properties_template=.CAPSULE_MAN, make_physics_properties_dynamic=true);
            test_ref = entity.ref;
            entity_phys_props := get_entity_physics_properties(test_ref);
            {
                using entity_phys_props;
                body_elasticity = 1.0;
                body_collider.type = .CAPSULE;
                body_collider.capsule.half_height = 10.0;
                body_collider.capsule.radius = 7.0;
            }
            // entity_phys_props.mass = IMMOVABLE_ENTITY_MASS;
            capsule := get_or_create_capsule_mesh(20.0, 7.0, 4.0);
            set_entity_meshes(entity.ref, .{data=capsule, albedo=.{tint=.{g=0.8}}});
            entity.position.z = 100.0;
        }
    }
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// command line procs

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }
using ImGui;

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