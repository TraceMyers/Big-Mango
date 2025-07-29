
// TODO: investigate possiblity of using rpmalloc as default allocator if it seems like a decent idea

main :: () {
    rm_log("starting...", header="STARTUP");
    defer rm_log("good exit", header="SHUTDOWN");
    set_working_directory(path_strip_filename(get_path_of_running_executable()));

    #if OS == .WINDOWS {
        Win32.SetProcessDPIAware();
        // Windows is very bad at thread-switching by default unless you do this. buh-buh-buh-buh-bad. buh-buh-buh-buh-bad
        Win32.timeBeginPeriod(1); // bad to the bone
    }

    pre_boot();

    startup_success := true;
    scope_system_init(_input,               *startup_success);
    scope_system_init(_vulkan,              *startup_success);
    scope_system_init(_imgui,               *startup_success);
    scope_system_init(_entities,            *startup_success);
    scope_system_init(_collision,           *startup_success);
    scope_system_init(_collision_grid,      *startup_success);
    scope_system_init(_scratch,             *startup_success);
    if !startup_success then return;

    per_frame_time = seconds_since_init();
    non_render_time = seconds_since_init();

    while !quit {
        update_input();
        scratch_think();
        solve_contacts();
        move_stuff();
        draw_dev_ui();
        end_frame();
    }
}

pre_boot :: () {
    // give the logger a proc to call after forming the log message
    rm_log_passthrough_callback = rm_log_callback;
    // call_rm_log_passthrough_only = true;

    // circular buffer, n messages, for the gui log
    // todo: bring this up to 1000+. all it needs is a way to cull messages that won't be rendered
    LOG_MESSAGE_COUNT :: 256;
    rm_log_messages = alloc_array(RM_Log_Message, LOG_MESSAGE_COUNT, program_runtime_allocator);
    
    initialize_nesting_allocator(*rm_log_message_allocator, context.default_allocator, 0, 32);
    // all allocations whose lifetime is the runtime of the program can just use this allocator. easy and fast.
    bump_allocator_initialize(*program_runtime_allocator);

    // the array of procedures corresponding to command line commands. set at runtime so that it doesn't need to be referred to at compile time (the constant array is generated at compile time). 
    command_line_procedures = COMMAND_LINE_PROCEDURES;
}

end_frame :: () {
    // console_window = GetConsoleWindow();
    // if console_window != null {
    //     Win32.SetWindowPos(console_window, null, 0, 0, 100, 100, 0);
    // }

    new_non_render_time := seconds_since_init();
    simulation_dt = exponential_interp(simulation_dt, xx (new_non_render_time - non_render_time), 2.0, delta_time);
    render_frame();
    non_render_time = seconds_since_init();

    entity_frame_turnover();

    reset_temporary_storage();
    game_frame_count += 1;

    // doing this after game_frame_count advances so the data are correct for the next generation of entities
    set_global_entities();

    new_time := seconds_since_init();
    delta_time = clamp((new_time - per_frame_time).(float32), 0.00001, 0.25);
    per_frame_time = new_time;
    if fixed_delta_time != 0.0 {
        delta_time = fixed_delta_time;
    }

    delta_times[dt_index] = delta_time;
    render_times[dt_index] = render_dt;
    simulation_times[dt_index] = simulation_dt;
    dt_index = increment_wrap(dt_index, 0, delta_times.count-1);
}

calc_fps :: () -> float32 {
    return 1.0 / delta_time;
}

calc_avg_fps :: () -> float32 {
    return 1.0 / calc_avg(delta_times);
}

calc_avg :: (times: []float) -> float {
    sum := 0.0;
    for times {
        sum += it;
    }
    return sum / xx times.count;
}

scope_system_init :: ($system_proc: Code, boot_success: *bool) #expand {
    if !boot_success.* then return;
    PROC_NAME :: #run code_string(system_proc);
    rm_log("%", PROC_NAME, header="STARTUP");
    proc := #insert system_proc;
    boot_success.* = proc(.STARTUP);
    if !boot_success.* {
        rm_log("startup failure. shutting down.", header="STARTUP"); 
        return; 
    } 
    `defer if boot_success.* {
        rm_log("%", PROC_NAME, header="SHUTDOWN");
        proc(.SHUTDOWN);
    }
}

Boot_Stage :: enum {
    STARTUP;
    SHUTDOWN;
}

fixed_delta_time := 0.0;

window: Window_Type;
console_window: Window_Type;
delta_time := 0.01;
game_frame_count: s32;
per_frame_time: float64;
non_render_time: float64;
quit := false;

simulation_dt: float;
render_dt: float;

DELTA_TIME_COUNT :: 120;
delta_times: [DELTA_TIME_COUNT]float32;
simulation_times: [DELTA_TIME_COUNT]float32;
render_times: [DELTA_TIME_COUNT]float32;
dt_index: s32;

#import "Basic"()();
#import "String";
#import "Red_Mango_Core";
#import "Vulkan_With_VMA"()(MEMORY_ALLOCATOR_DEBUG=true, USE_LOCAL_VULKAN_DYNAMIC_LIB=true);
// #import "Vulkan_With_VMA"()(MEMORY_ALLOCATOR_DEBUG=false, USE_LOCAL_VULKAN_DYNAMIC_LIB=true);
#import "Window_Creation";
#import "Math";
#import "File";
#import "Thread";
#import "System";
#import "Random";
#import "stb_image";
#import "xxHash";
#import "Flat_Pool";
#import "Sort";
ImGui :: #import "ImGui_VulkanWin32";
Input :: #import "Input";

#if OS == .WINDOWS {
    Win32 :: #import "Windows";
}
Zlib :: #import "zlib";

#load "constants.jai";
#load "physics_properties.jai";
#load "input.jai";
#load "vulkan.jai";
#load "imgui/imgui_impl.jai";
#load "entity_types.jai";
#load "entity.jai";
#load "entity_creature.jai";
#load "camera.jai";
#load "load_assets.jai";
#load "world.jai";
#load "scratch.jai";
#load "allocators.jai";
#load "physics_new.jai";
#load "draw.jai";
#load "entity_control.jai";
// #load "raycast.jai";
#load "entities/entity_button.jai";
#load "add_to_context.jai";
#load "collision_types.jai";
#load "collision.jai";
#load "collision_grid.jai";
// #load "overlap.jai";

kernel32 :: #system_library "kernel32";
GetConsoleWindow :: () -> Win32.HWND #foreign kernel32;