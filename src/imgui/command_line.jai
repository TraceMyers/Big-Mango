
// ---------------------------------------------------------------------------------------------------------------------
#scope_file // ---------------------------------------------------------------------------------------------- SCOPE_FILE
// ---------------------------------------------------------------------------------------------------------------------

using ImGui;

// ---------------------------------------------------------------------------------------------------------------------
#scope_export // ------------------------------------------------------------------------------------------ SCOPE_EXPORT
// ---------------------------------------------------------------------------------------------------------------------

add_command_line :: (main_menu_height: float, sidebar_width: float32, perf_readout_width: float32) -> input_begin_x: float32, bar_height: float32 {
    if input_focus != .COMMAND_LINE then return 0,0;
    if !is_set(*dev_ui_enabled, .CMD) {
        return 0,0;
    }

    scope_set_alpha(dev_ui_opacities[Dev_UI_Module.CMD]);

    // PushStyleColor(.WindowBg, .{xyz=DEEP_DARK_BLUE.vec3, w=1.0});
    // defer PopStyleColor();

    Begin("CommandLine_InputBar", flags=.NoTitleBar | .NoMove | .NoResize | .NoScrollbar);
    defer End();

    line_height := GetFrameHeight() * 2 - 2;
    is_cli_focused := IsWindowFocused();
    SetWindowPos(.{sidebar_width, main_menu_height});

    // SetCursorPos(.{sidebar_width, line_height*0.1});
    // PushStyleColor(.Text, 0xff_8f_a2_8a);
    cmd_header_text := " cmd: ";
    cmd_header_text_size := text_size(cmd_header_text);
    Text(cmd_header_text);
    // PopStyleColor();

    input_text_x_offset := cmd_header_text_size.x - 12;
    SetCursorPos(.{input_text_x_offset, 6});

    // setting the label width to zero. doing custom label
    PushItemWidth(-1);
    PushStyleVar(.WindowPadding, .{});

    if InputText("##CommandLine_InputText", command_line_text_buffer.data, command_line_text_buffer.count, .EnterReturnsTrue | .CallbackCompletion, command_line_autocomplete_callback) {
        input_str := string.{c_style_strlen(command_line_text_buffer.data), command_line_text_buffer.data};
        tokens := tokenize_and_trim(input_str, #char " ");
        command_has_prefix: bool;
        if begins_with(input_str, "vtoggle") || begins_with(input_str, "vset") {
            command_has_prefix = true;
        }
        if (!command_has_prefix && tokens.count > 0) || tokens.count > 1 {
            COMMAND_LINE_ARGS_MAX_COUNT :: 16;
            assert(tokens.count-1 <= COMMAND_LINE_ARGS_MAX_COUNT);
            args: [COMMAND_LINE_ARGS_MAX_COUNT]Command_Line_Argument;
            args_bound := bound_array(args);

            iter_start := ifx command_has_prefix then 2 else 1;
            if tokens.count > iter_start then for iter_start..tokens.count-1 {
                // todo: get types of params from the procedure struct
                arg := bound_array_add(*args_bound);
                // parse_... procs consume the input
                og_str := tokens[it];
                arg._int, arg.parse_int_success = parse_int(*og_str);
                og_str = tokens[it];
                arg._float, arg.parse_float_success = parse_float(*og_str);
                arg._string = tokens[it];
            }

            hashable_input: string;
            if command_has_prefix {
                hashable_input = tprint("% %", tokens[0], tokens[1]);
            } else {
                hashable_input = tokens[0];
            }
            rm_log("calling %", hashable_input);
            hash := native_XXH64(hashable_input.data, xx hashable_input.count, 0xDEADBEEF);
            if !try_call_command_line_procedure(hash, args_bound.array) {
                rm_warning("call failure");
            }
            memset(command_line_text_buffer.data, 0, command_line_text_buffer.count);
        }
        if !Input.input_button_states[Input.Key_Code.SHIFT] {
            revert_input_focus();
        }
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

get_command_line_suggestions :: () -> []*Command_Line_Procedure {
    out_procs: []*Command_Line_Procedure;

    input_mem := string.{c_style_strlen(command_line_text_buffer.data), command_line_text_buffer.data};
    input_tokens := tokenize_and_trim(input_mem, #char " ");
    if input_tokens.count == 0 || input_tokens[0].count == 0 {
        return out_procs;
    }

    Matching_Procedure :: struct {
        proc: s32;
        score: s32;
    }
    matching_procedures := array_alloc(Matching_Procedure, command_line_procedures.count,, temp);
    
    out_count: s32;
    for proc : command_line_procedures {
        i := find_index_from_left(proc.name, input_tokens[0], true);
        if i != -1 {
            score : s32 = proc.name.count.(s32) - i.(s32);
            if input_tokens.count > 1 {
                for 1..input_tokens.count-1 {
                    token_index := find_index_from_left(proc.name, input_tokens[it], true);
                    if token_index != -1 {
                        score += proc.name.count.(s32) - token_index.(s32);
                    }
                }
            }
            matching_procedures[out_count] = .{xx it_index, score};
            out_count += 1;
        }
    }

    if out_count == 0 {
        return out_procs;
    }

    matching_procedures.count = out_count;
    quick_sort(matching_procedures, (a, b) => b.score - a.score);
    out_procs = array_alloc(*Command_Line_Procedure, matching_procedures.count,, temp);
    for matching_procedures {
        out_procs[it_index] = *command_line_procedures[it.proc];
    }

    return out_procs;
}

add_command_line_input_suggestions :: (input_begin_x: float32, input_bar_height: float32) -> suggestion_count: s32 {
    suggestions := get_command_line_suggestions();
    if suggestions.count == 0 {
        return 0;
    }

    is_open := BeginChild("##CommandLine_InputSuggestions"/*, flags=.NoTitleBar | .NoResize | .NoInputs | .NoNav*/);
    defer EndChild();
    if !is_open then return 0;

    for suggestions {
        SetCursorPosX(input_begin_x-4);
        Text(it.name);
    }

    return xx suggestions.count;
}

copy_best_suggestion_to_command_line_input :: (buf: *u8, size: s64) {
    suggestions := get_command_line_suggestions();

    if suggestions.count > 0 {
        proc_name := suggestions[0].name;
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
