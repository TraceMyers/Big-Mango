
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

    // pre-boot config
    command_line_procedures = COMMAND_LINE_PROCEDURES;
    rm_log_passthrough_callback = rm_log_callback;
    call_rm_log_passthrough_only = true;
    rm_log_messages = alloc_array(RM_Log_Message, 256, program_runtime_allocator);
    initialize_nesting_allocator(*rm_log_message_allocator, context.default_allocator, 0, 32);

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

        populate_potential_contacts();
        solve_potential_contacts();
        move_entities();

        height := 20.8;
        radius := 3.0;
        pc_middle := player_character.position + WORLD_UP * height;

        forward := fore_direction(*player_character);
        color := Color4f.{0.6, 0.11, 0.9, 1.0};
        pt_a := WORLD_UP * radius;
        pt_b := WORLD_UP * (height - radius);
        draw_capsule(.{pt_a, pt_b, radius, .{130, 11, 190, 100}});
        // draw_cylinder(*player_character.physics_properties.body_collider, *player_character.position, *forward.xy, *color, 50);

        for npcs {
            forward := fore_direction(*it);
            color := Color4f.{0.6, 0.11, 0.9, 1.0};
            // draw_cylinder(*it.physics_properties.body_collider, *it.position, *forward.xy, *color, 50);
        }

        new_non_render_time := seconds_since_init();
        simulation_dt = exponential_interp(simulation_dt, xx (new_non_render_time - non_render_time), 2.0, delta_time);
        render_frame();
        non_render_time = seconds_since_init();

        new_time := seconds_since_init();
        delta_time = clamp((new_time - per_frame_time).(float32), 0.00001, 0.25);
        per_frame_time = new_time;
        game_frame_count += 1;

        delta_times[dt_index] = delta_time;
        simulation_times[dt_index] = simulation_dt;
        render_times[dt_index] = render_dt;
        dt_index = increment_wrap(dt_index, 0, DELTA_TIME_COUNT-1);

        reset_temporary_storage();
    }
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

window: Window_Type;
delta_time := 0.01;
game_frame_count: s64;
per_frame_time: float64;
non_render_time: float64;
quit := false;

camera: Entity;
player_character: Entity;
npcs: [..]Entity;

simulation_dt: float;
render_dt: float;

DELTA_TIME_COUNT :: 120;
delta_times: [DELTA_TIME_COUNT]float32;
simulation_times: [DELTA_TIME_COUNT]float32;
render_times: [DELTA_TIME_COUNT]float32;
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
#load "entity.jai";
#load "camera.jai";
#load "load_assets.jai";
#load "world.jai";
#load "scratch.jai";
#load "allocators.jai";
#load "collision.jai";
#load "draw.jai";
#load "entity_control.jai";