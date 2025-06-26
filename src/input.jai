
control_mode := Control_Mode.CHARACTER;
input_focus := Input_Focus.GAME;
previous_input_focus: Input_Focus;

Input_Focus :: enum {
    GAME;
    COMMAND_LINE;
    LOG_FILTER;
}

Control_Mode :: enum {
    FREE_FLY;
    CHARACTER;
}

boot_input :: (stage: Boot_Stage) -> bool {
    if stage == .STARTUP {
        window = create_window(1920, 1200, "a butt", 27, -1300);
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

update_window_events :: (delta_time: float) {
    Input.update_window_events();

    for Input.events_this_frame {
        imgui_process_event(it);
        if it.type == .QUIT then quit = true;

        if it.type == .KEYBOARD {
            if it.key_pressed {
                if it.key_code == .ESCAPE then quit = true;
                if it.key_code == {
                case .F1;
                    if input_focus == .GAME then control_mode = .FREE_FLY;
                case .F2;
                    if input_focus == .GAME then control_mode = .CHARACTER;
                case #char "M";
                    if input_focus == .GAME && control_mode == .FREE_FLY {
                        do_mouse_move = !do_mouse_move;
                    }
                case #char "`";
                    toggle_input_focus(.COMMAND_LINE);
                }
            }
        }
    }

    if control_mode == .FREE_FLY {
        camera.projection = .PERSPECTIVE;
        camera.perspective.vertical_fov = 90;
        if input_focus == .GAME {
            speed := 100.0;
            dt_speed := speed * delta_time;
            if Input.input_button_states[#char "W"] & .DOWN {
                camera.position += fore_direction(*camera) * dt_speed;
            }
            if Input.input_button_states[#char "S"] & .DOWN {
                camera.position -= fore_direction(*camera) * dt_speed;
            }
            if Input.input_button_states[#char "D"] & .DOWN {
                camera.position += right_direction(*camera) * dt_speed;
            }
            if Input.input_button_states[#char "A"] & .DOWN {
                camera.position -= right_direction(*camera) * dt_speed;
            } 
            if Input.input_button_states[#char "Z"] & .DOWN {
                camera.position += up_direction(*camera) * dt_speed;
            }
            if Input.input_button_states[#char "X"] & .DOWN {
                camera.position -= up_direction(*camera) * dt_speed;
            }

            if do_mouse_move {
                rot_speed := 0.2;
                rot_dt_speed := rot_speed * delta_time;
                if abs(Input.mouse_delta_x) > 0 {
                    angle := -rot_dt_speed * Input.mouse_delta_x.(float);
                    rotate(*camera, WORLD_UP, angle);
                }
                if abs(Input.mouse_delta_y) > 0 {
                    angle := -rot_dt_speed * Input.mouse_delta_y.(float);
                    rotate(*camera, right_direction_xy(*camera), angle);
                }
            }
        }
    } else {
        camera.projection = .ORTHOGRAPHIC;
        cos_t := cos(PI/4);
        sin_t := sin(PI/4);
        set_orientation(*camera, .{0,sin_t,-cos_t}, .{0,cos_t,sin_t});
        camera.orthographic.scale = 10;

        if input_focus == .GAME {
            target := player_character.orientation;
            camera_xy_orientation: Quaternion;
            set_orientation(*camera_xy_orientation, fore_direction_xy(*camera.orientation), .{0,0,1});

            speed := 24.0;
            dt_speed := speed * delta_time;
            move_dir: Vector3;

            if Input.input_button_states[#char "W"] & .DOWN {
                target = camera_xy_orientation;
                move_dir.xy += fore_direction_xy(*target).xy;
            }
            if Input.input_button_states[#char "S"] & .DOWN {
                target = camera_xy_orientation;
                rotate(*target, .{0,0,1}, PI);
                move_dir.xy += fore_direction_xy(*target).xy;
            }
            if Input.input_button_states[#char "D"] & .DOWN {
                target = camera_xy_orientation;
                rotate(*target, .{0,0,1}, -PI/2);
                move_dir.xy += fore_direction_xy(*target).xy;
            }
            if Input.input_button_states[#char "A"] & .DOWN {
                target = camera_xy_orientation;
                rotate(*target, .{0,0,1}, PI/2);
                move_dir.xy += fore_direction_xy(*target).xy;
            }

            if move_dir.xy != .{0,0} {
                move_dir.xy = normalize(move_dir.xy);
                target = make_quat(.{move_dir.x, move_dir.y, 0}, .{0,0,1});
                player_character.position.xy += move_dir.xy * dt_speed;
            }

            rot_speed := 6.5 * PI;
            interp_rotate(*player_character, target, rot_speed, delta_time);

            target_camera_pos: Vector3 = ---;
            target_camera_pos.xy = player_character.position.xy;
            target_camera_pos.xy -= fore_direction(*camera).xy * 30.0;
            target_camera_pos.z = player_character.position.z + 60.0;
            camera.position = exponential_interp(camera.position, target_camera_pos, 4.0, delta_time);
        }
    }

    // point_at(*camera, .{});

    resizes := Input.get_window_resizes();  // We might want to collapse all resizes down to 1 for each window, but we don't currently do this, I think.
    for record: resizes {
        if record.window == window {
            window_width = record.width;
            window_height = record.height;
        }
    }
}

get_window_dimensions :: () -> Int_Vector2 {
    return .{window_width, window_height};
}

// todo: same input counter
rm_log_callback :: (text: string) {
    if log_paused then return;

    {
        using rm_log_messages[rm_log_message_top];

        rm_log_message_prev := decrement_wrap(rm_log_message_top, 0, xx (rm_log_messages.count-1));
        prev_message, _ := get_rm_log_message(rm_log_message_prev);
        if text == prev_message {
            rm_log_messages[rm_log_message_prev].repeat_count += 1;
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
