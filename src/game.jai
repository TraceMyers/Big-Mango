
// I feel silly for taking so long to see this language, compiler, and module set for what it is: a gift 
// that paves the way toward what I want to do.

main :: () {
    setup_success := true;
    scope_system_setup(Window, *setup_success);
    scope_system_setup(Vulkan, *setup_success);
    if !setup_success then return;

    per_frame_time = seconds_since_init();

    while !quit {
        update_window_events(delta_time);

        vk_render_frame();

        new_time := seconds_since_init();
        delta_time = clamp((new_time - per_frame_time).(float32), 0.0, 1.0);
        per_frame_time = new_time;

        reset_temporary_storage();
        sleep_milliseconds(1);
    }
}

Window :: struct {
    scope_initialize :: () -> bool {
        window = create_window(256, 256, "a butt");
        return window != null;
    }
    scope_deinitialize :: () {}
}

window: Window_Type;
delta_time := 0.01;
per_frame_time: float64;
quit := false;

#import "Basic";
#import "String";
#import "Red_Mango_Core";
#import "Window_Creation";
#import "Math";
#import "File";
Input :: #import "Input";

#if OS == .WINDOWS {
    #import "Windows";
}

#load "input.jai";
#load "vulkan.jai";