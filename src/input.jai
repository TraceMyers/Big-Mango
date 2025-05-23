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
}