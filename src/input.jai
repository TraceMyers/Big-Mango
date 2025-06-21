
CONTROL_MODE :: enum {
    FREE_FLY;
    CHARACTER;
}
control_mode := CONTROL_MODE.CHARACTER;

boot_input :: (stage: Boot_Stage) -> bool {
    if stage == .STARTUP {
        window = create_window(1024, 1024, "a butt");
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
                    control_mode = .FREE_FLY;
                case .F2;
                    control_mode = .CHARACTER;
                }
                if control_mode == .FREE_FLY {
                    if it.key_code == #char "M" {
                        do_mouse_move = !do_mouse_move;
                    }
                }
            }
        }
    }

    if control_mode == .FREE_FLY {
        camera.projection = .PERSPECTIVE;
        camera.perspective.vertical_fov = 90;
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
                // rm_log("delta x: %", Input.mouse_delta_x);
                // rm_log("speed: %, dt: %, rot_dt_speed: %, angle: %", rot_speed, delta_time, rot_dt_speed, angle);
            }
            if abs(Input.mouse_delta_y) > 0 {
                angle := -rot_dt_speed * Input.mouse_delta_y.(float);
                rotate(*camera, right_direction_xy(*camera), angle);
                // rm_log("delta y: %", Input.mouse_delta_y);
            }
        }
    } else {

        camera.projection = .ORTHOGRAPHIC;
        camera.orthographic.scale = 10;
        target := player_character.orientation;
        camera_xy_orientation: Quaternion;
        set_orientation(*camera_xy_orientation, fore_direction_xy(*camera.orientation), .{0,0,1});

        speed := 24.0;
        dt_speed := speed * delta_time;
        move_dir: Vector3;

        if Input.input_button_states[#char "W"] & .DOWN {
            target = camera_xy_orientation;
            rotate(*target, .{0,0,1}, -PI/2);
            move_dir.xy += -right_direction_xy(*target).xy;
        }
        if Input.input_button_states[#char "S"] & .DOWN {
            target = camera_xy_orientation;
            rotate(*target, .{0,0,1}, PI/2);
            move_dir.xy += -right_direction_xy(*target).xy;
        }
        if Input.input_button_states[#char "D"] & .DOWN {
            target = camera_xy_orientation;
            rotate(*target, .{0,0,1}, PI);
            move_dir.xy += -right_direction_xy(*target).xy;
        }
        if Input.input_button_states[#char "A"] & .DOWN {
            target = camera_xy_orientation;
            move_dir.xy += -right_direction_xy(*target).xy;
        }

        if move_dir.xy != .{0,0} {
            move_dir.xy = normalize(move_dir.xy);
            target = make_quat(.{move_dir.y, -move_dir.x, 0}, .{0,0,1});
            player_character.position.xy += move_dir.xy * dt_speed;
        }

        rot_speed := 6.5 * PI;
        interp_rotate(*player_character, target, rot_speed, delta_time);

        target_camera_pos: Vector3 = ---;
        target_camera_pos.xy = player_character.position.xy;
        target_camera_pos.xy -= fore_direction(*camera).xy * 30.0;
        target_camera_pos.z = player_character.position.z + 60.0;
        camera.position = exponential_interp(camera.position, target_camera_pos, 6.0, delta_time);
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


#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

window_width: s32;
window_height: s32;

do_mouse_move := true;
