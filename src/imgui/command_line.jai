
add_command_line :: (main_menu_height: float, sidebar_width: float32, perf_readout_width: float32) -> input_begin_x: float32, bar_height: float32 {
    if input_focus != .COMMAND_LINE then return 0,0;

    PushStyleColor(.WindowBg, .{xyz=DEEP_DARK_BLUE.vec3, w=0.9});
    defer PopStyleColor();

    Begin("CommandLine_InputBar", flags=.NoTitleBar | .NoMove | .NoResize);
    defer End();

    line_height := GetFrameHeight() * 2 - 2;
    is_cli_focused := IsWindowFocused();
    SetWindowPos(.{sidebar_width, main_menu_height});

    // SetCursorPos(.{sidebar_width, line_height*0.1});
    PushStyleColor(.Text, 0xff_8f_a2_8a);
    cmd_header_text := " cmd: ";
    cmd_header_text_size := text_size(cmd_header_text);
    Text(cmd_header_text);
    PopStyleColor();

    input_text_x_offset := cmd_header_text_size.x - 12;
    SetCursorPos(.{input_text_x_offset, 6});

    // setting the label width to zero. doing custom label
    PushItemWidth(-1);
    PushStyleVar(.WindowPadding, .{});

    reclaim_focus: bool;
    if InputText("##CommandLine_InputText", command_line_text_buffer.data, command_line_text_buffer.count, .EnterReturnsTrue | .CallbackCompletion, command_line_autocomplete_callback) {
        input_str := string.{c_style_strlen(command_line_text_buffer.data), command_line_text_buffer.data};
        tokens := tokenize_and_trim(input_str, #char " ");
        if tokens.count > 0 {
            COMMAND_LINE_ARGS_MAX_COUNT :: 16;
            assert(tokens.count-1 <= COMMAND_LINE_ARGS_MAX_COUNT);
            args: [COMMAND_LINE_ARGS_MAX_COUNT]Command_Line_Argument;
            args_bound := bound_array(args);

            if tokens.count > 1 then for 1..tokens.count-1 {
                // todo: get types of params from the procedure struct
                arg := bound_array_add(*args_bound);
                // parse_... procs consume the input
                og_str := tokens[it];
                arg._int, arg.parse_int_success = parse_int(*og_str);
                og_str = tokens[it];
                arg._float, arg.parse_float_success = parse_float(*og_str);
                arg._string = tokens[it];
            }

            rm_log("calling %", tokens[0]);
            if !try_call_command_line_procedure(tokens[0], args_bound.array) {
                rm_warning("call failure");
            }
            memset(command_line_text_buffer.data, 0, command_line_text_buffer.count);
        }

        reclaim_focus = true;
    }
    PopStyleVar();
    PopItemWidth();

    // force focus onto the InputText always
    SetItemDefaultFocus();
    SetKeyboardFocusHere(-1);

    window_size: Vector2;
    app_window_dims := get_window_dimensions();
    window_size.x = xx app_window_dims.x - (perf_readout_width + sidebar_width);
    window_size.y = line_height;

    suggestion_count := add_command_line_input_suggestions(input_text_x_offset, window_size.y);

    window_size.y += suggestion_count * GetFrameHeight();
    SetWindowSize(window_size);

    return input_text_x_offset, window_size.y;
}

add_command_line_input_suggestions :: (input_begin_x: float32, input_bar_height: float32) -> suggestion_count: s32 {
    input_mem := string.{c_style_strlen(command_line_text_buffer.data), command_line_text_buffer.data};
    input_tokens := tokenize_and_trim(input_mem, #char " ");
    if input_tokens.count == 0 || input_tokens[0].count == 0 {
        return 0;
    }

    PushStyleColor(.ChildBg, .{xyz=DARK_GREY_BLUE.vec3, w=0.9});
    defer PopStyleColor();

    is_open := BeginChild("##CommandLine_InputSuggestions"/*, flags=.NoTitleBar | .NoResize | .NoInputs | .NoNav*/);
    defer EndChild();
    if !is_open then return 0;

    out_count: s32;
    best_suggestion_index: s64 = -1;
    best_suggestion_matched_at: s64 = S64_MAX;

    Matching_Procedure :: struct {
        proc: s32;
        index_of_matched_pattern: s32; // the lower the matched index of the pattern, the better
    }
    matching_procedures := alloc_array(Matching_Procedure, command_line_procedures.count, temp);
    
    for command_line_procedures {
        i := find_index_from_left(it.name, input_tokens[0], true);
        if i != -1 {
            matching_procedures[out_count] = .{xx it_index, xx i};
            out_count += 1;
        }
    }

    matching_procedures.count = out_count;
    quick_sort(matching_procedures, (a, b) => a.index_of_matched_pattern - b.index_of_matched_pattern);
    for matching_procedures {
        SetCursorPosX(input_begin_x-4);
        Text(command_line_procedures[it.proc].name);
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

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

using ImGui;
