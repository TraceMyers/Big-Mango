
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
                if it.key_code == #char "M" {
                    do_mouse_move = !do_mouse_move;
                }
            }
        }
    }

    speed := 4.0;
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
        if abs(Input.mouse_delta_x) > 0 {
            angle := -dt_speed * 0.4 * Input.mouse_delta_x.(float) * (180.0 / PI);
            rotate(*camera, WORLD_UP, angle);
        }
        if abs(Input.mouse_delta_y) > 0 {
            angle := -dt_speed * 0.4 * Input.mouse_delta_y.(float) * (180.0 / PI);
            rotate(*camera, right_direction_xy(*camera), angle);
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


#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

window_width: s32;
window_height: s32;

do_mouse_move := true;
