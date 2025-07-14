
DEFAULT_CONTROL_MODE :: Control_Mode.FIRST_PERSON;
control_mode := DEFAULT_CONTROL_MODE;
prev_control_mode := Control_Mode.FREE_FLY;
input_focus := Input_Focus.GAME;
previous_input_focus: Input_Focus;
mouse_look_locked: bool;

Input_Focus :: enum {
    GAME;
    COMMAND_LINE;
    LOG_FILTER;
}

Control_Mode :: enum {
    FREE_FLY;
    FIRST_PERSON;
    ORTHO_YZ_45_DOWN;
    ORTHO_YZ;
    ORTHO_XZ;
    ORTHO_XY;
}

boot_input :: (stage: Boot_Stage) -> bool {
    if stage == .STARTUP {
        // NOTE: the window is born into this world through the fires of whatever monitor it is initially displayed on. as a result, it appears that spawning the window on a monitor whose display adapter isn't your big beefy graphics card I think means the graphics card is being forced to communicate through the integrated gpu or I don't know but anyway it totally fucks up the stability of the moving images. like, it looked like I was getting some horrific per-pixel-row-blend of past and present images.
        // window = create_window(1920, 1200, "a butt", 90, -1300);
        window = create_window(1920, 1200, "a butt", 0, 0);
        // get initial dimensions because we won't update this until the first resize
        if window != null {
            _, _, window_width=, window_height=, success := get_dimensions(window, true);
            return true;
        } 
        return false;
    } else {
        return true;
    }
}

move_window :: (new_pos: Int_Vector2) {
    rect: Win32.RECT;
    Win32.GetClientRect(window, *rect);
    // Win32.SetWindowPos(window, null, 90, -1300, rect.right-rect.left+16, rect.bottom-rect.top+39, 0);
    Win32.SetWindowPos(window, null, new_pos.x, new_pos.y, rect.right-rect.left+16, rect.bottom-rect.top+39, 0);
}

// returns true if focus was changed
set_input_focus :: (focus: Input_Focus) -> bool {
    if input_focus != focus {
        previous_input_focus = input_focus;
        input_focus = focus;
        return true;
    }
    return false;
}

// returns true if toggled on, false if toggled off
toggle_input_focus :: (focus: Input_Focus) -> bool {
    if !set_input_focus(focus) {
        revert_input_focus();
        return false;
    }
    return true;
}

revert_input_focus :: () {
    input_focus = .GAME;
    previous_input_focus = .GAME;
}

update_input :: () {
    Input.update_window_events();

    prev_control_mode = control_mode;

    for Input.events_this_frame {
        imgui_process_event(it);
        if it.type == .QUIT then quit = true;

        if it.type == .KEYBOARD {
            if it.key_pressed {
                if it.key_code == .ESCAPE then quit = true;
                if input_focus == .GAME {
                    if it.key_code == {
                    case .F1;
                        control_mode = .ORTHO_YZ_45_DOWN;
                    case .F2;
                        control_mode = .ORTHO_YZ;
                    case .F3;
                        control_mode = .ORTHO_XZ;
                    case .F4;
                        control_mode = .ORTHO_XY;
                    case .F5;
                        control_mode = .FIRST_PERSON;
                    case .F6;
                        control_mode = .FREE_FLY;
                    case #char "M";
                        if (control_mode == .FREE_FLY || control_mode == .FIRST_PERSON) {
                            toggle(*mouse_look_locked);
                        }
                    }
                    if control_mode == .FIRST_PERSON {
                        if it.key_code == {
                        case .SPACEBAR;
                            jump_queued = true;
                            jump_queued_at_time = xx seconds_since_init();
                        }
                    }
                }
                if it.key_code == #char "`" {
                    toggle_input_focus(.COMMAND_LINE);
                }
            }
        }
    }
    // NOTE: these resizes give the drawable (client) rect, not the full size
    resizes := Input.get_window_resizes();  // We might want to collapse all resizes down to 1 for each window, but we don't currently do this, I think.
    for record: resizes {
        if record.window == window {
            // window_width = record.width;
            // window_height = record.height;
        }
    }
    if resizes.count > 0 {
        _, _, window_width=, window_height=, success := get_dimensions(window, true);
        if !success {
            rm_error("failed to get window dimensions after resize");
        }
    }

    process_entity_input();
}

get_window_dimensions :: () -> Int_Vector2 {
    return .{window_width, window_height};
}

rm_log_callback :: (text: string) {
    if log_paused then return;

    {
        using rm_log_messages[rm_log_message_top];

        rm_log_message_prev := decrement_wrap(rm_log_message_top, 0, xx (rm_log_messages.count-1));
        prev_message, _ := get_rm_log_message(rm_log_message_prev);
        if text == prev_message {
            repeat_count += 1;
            return;
        }

        if string_count > 0 {
            na_free(*rm_log_message_allocator, *allocation_ref);
        } else {
            assert(allocation_ref.data == null);
        }

        string_count = xx text.count;
        if text.count > 0 {
            repeat_count = 1;
            allocation_ref = na_alloc(*rm_log_message_allocator, string_count);
            memcpy(allocation_ref.data, text.data, string_count);

        }
        rm_log_message_top = increment_wrap(rm_log_message_top, 0, xx (rm_log_messages.count-1));
    }
}

RM_Log_Message :: struct {
    repeat_count: s32;
    string_count: s32;
    allocation_ref: Nested_Allocation_Ref;
}

get_rm_log_message :: inline (i: s64) -> string, s32 {
    using rm_log_messages[i];
    return string.{string_count, allocation_ref.data}, repeat_count;
}

rm_log_messages: []RM_Log_Message;
rm_log_message_top: s32;
rm_log_message_allocator: Nesting_Allocator;

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// command line procs

set_control_mode :: (args: []Command_Line_Argument) {
    init_command_line_proc_or_return(args, 1);
    cm, success := try_parse_command_line_arg(*args[0], Control_Mode);
    if success then control_mode = cm;
} @command_line

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

window_width: s32;
window_height: s32;

do_mouse_move := true;
