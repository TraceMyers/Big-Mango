
// I feel silly for taking so long to see this language, compiler, and module set for what it is: a gift 
// that paves the way toward what I want to do.
// TODO: investigate possiblity of using rpmalloc as default allocator if it seems like a decent idea

main :: () {
    defer rm_log("good exit");
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
    }
}


window: Window_Type;
delta_time := 0.01;
per_frame_time: float64;
quit := false;

#import "Basic";
#import "String";
#import "Red_Mango_Core";
#import "Vulkan_With_VMA"()(MEMORY_ALLOCATOR_DEBUG=true, USE_LOCAL_VULKAN_DYNAMIC_LIB=false);
#import "Window_Creation";
#import "Math";
#import "File";
#import "Thread";
Input :: #import "Input";

#if OS == .WINDOWS {
    #import "Windows";
}

#load "input.jai";
#load "vulkan.jai";
