
// I feel silly for taking so long to see this language, compiler, and module set for what it is: a gift 
// that paves the way toward what I want to do.
// TODO: investigate possiblity of using rpmalloc as default allocator if it seems like a decent idea

main :: () {
    defer rm_log("good exit", header="SHUTDOWN");
    set_working_directory(path_strip_filename(get_path_of_running_executable()));
    #if OS == .WINDOWS {
        Win32.SetProcessDPIAware();
        // Windows is very bad at thread-switching by default unless you do this. Thad.
        Win32.timeBeginPeriod(1);
    }

    command_line_procedures = COMMAND_LINE_PROCEDURES;

    startup_success := true;
    scope_system_init(boot_allocators,  *startup_success);
    scope_system_init(boot_input,       *startup_success);
    scope_system_init(boot_vulkan,      *startup_success);
    scope_system_init(boot_imgui,       *startup_success);
    scope_system_init(boot_entities,    *startup_success);
    if !startup_success then return;

    scratch_init_game();

    per_frame_time = seconds_since_init();
    non_render_time = seconds_since_init();

    while !quit {
        update_window_events(delta_time);
        imgui_draw();

        pc_hips_maybe := player_character.position + WORLD_UP * 20.0;
        draw_line(pc_hips_maybe, pc_hips_maybe + fore_direction(*player_character) * 50.0, .{1,0,0,1}, .{0,0,1,1});

        new_non_render_time := seconds_since_init();
        non_render_dt = xx (new_non_render_time - non_render_time);
        render_frame();
        non_render_time = seconds_since_init();

        new_time := seconds_since_init();
        delta_time = clamp((new_time - per_frame_time).(float32), 0.00001, 0.25);
        per_frame_time = new_time;
        game_frame_count += 1;

        delta_times[dt_index] = delta_time;
        dt_index = increment_wrap(dt_index, 0, DELTA_TIME_COUNT-1);

        reset_temporary_storage();
    }
}

calc_fps :: () -> float32 {
    return 1.0 / delta_time;
}

calc_avg_fps :: () -> float32 {
    return 1.0 / calc_avg_delta_time();
}

calc_avg_delta_time :: () -> float32 {
    sum := 0.0;
    for delta_times {
        sum += it;
    }
    return sum / xx DELTA_TIME_COUNT;
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

window: Window_Type;
delta_time := 0.01;
game_frame_count: s64;
per_frame_time: float64;
non_render_time: float64;
quit := false;

camera: Entity;
player_character: Entity;

non_render_dt: float;

DELTA_TIME_COUNT :: 64;
delta_times: [DELTA_TIME_COUNT]float32;
dt_index: s32;

#import "Basic";
#import "String";
#import "Red_Mango_Core";
#import "Vulkan_With_VMA"()(MEMORY_ALLOCATOR_DEBUG=true, USE_LOCAL_VULKAN_DYNAMIC_LIB=true);
#import "Window_Creation";
#import "Math";
#import "File";
#import "Thread";
#import "System";
#import "Random";
#import "stb_image";
#import "xxHash";
#import "Flat_Pool";
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
#load "imgui_impl.jai";
#load "entity.jai";
#load "camera.jai";
#load "load_assets.jai";
#load "world.jai";
#load "scratch.jai";
#load "allocators.jai";
#load "collision.jai";
#load "draw.jai";