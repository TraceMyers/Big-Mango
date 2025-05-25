
window_resizing: bool;

update_window_events :: (delta_time: float) {
    Input.update_window_events();

    for Input.events_this_frame {
        if it.type == .QUIT then quit = true;
        if it.type == .KEYBOARD {
            if it.key_pressed {
                if it.key_code == .ESCAPE then quit = true;
            }
        }

    }

    window_resizing = false;
    resizes := Input.get_window_resizes();  // We might want to collapse all resizes down to 1 for each window, but we don't currently do this, I think.
    for record: resizes {
        if record.window == window {
            window_width = record.width;
            window_height = record.height;
            window_resizing = true;
        }
    }
}

get_window_dimensions :: () -> Int_Vector2 {
    return .{window_width, window_height};
}

#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

window_width: s32;
window_height: s32;
