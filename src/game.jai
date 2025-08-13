
// TODO: investigate possiblity of using rpmalloc as default allocator if it seems like a decent idea
// TODO: global entity pointers need to be re-set every frame like before
// TODO: entity fabrication tool would be nice.

main :: () {
    rm_log("starting...", header="STARTUP");
    defer rm_log("good exit", header="SHUTDOWN");
    set_working_directory(path_strip_filename(get_path_of_running_executable()));

    #if BUILDVAR_DO_PROFILING {
        scope_timer_stack_diffs.count = 0;
    }

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
        respond_to_scope_timer_commands();
        scope_timer("game frame", true);
        begin_frame();
        update_input();
        process_entity_input();
        entity_ai_updates();
        update_thinks();
        solve_contacts();
        scratch_think();
        draw_dev_ui();
        do_debug_draws();
        end_frame();
    }

    report_scope_times();
}

pre_boot :: () {
    // give the logger a proc to call after forming the log message
    rm_log_passthrough_callback = rm_log_callback;
    // call_rm_log_passthrough_only = true;

    Win32.QueryPerformanceFrequency(*cpu_frequency);
    #if BUILDVAR_DO_PROFILING {
        array_reserve(*scope_timers, 4096);
        array_reserve(*scope_timer_stack_diffs, 4096);
    }

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

respond_to_scope_timer_commands :: inline () {
    if profiling_on {
        is_profiling_on = true;
        profiling_on = false;
        profiling_started_at_time = seconds_since_init();
    }
    if profiling_off {
        is_profiling_on = false;
        profiling_off = false;
    }
}

begin_frame :: () {
    scope_timer();

    array_reserve(*entity_removal_queue, 128);
}

end_frame :: () {
    scope_timer();

    new_non_render_time := seconds_since_init();
    simulation_dt = exponential_interp(simulation_dt, xx (new_non_render_time - non_render_time), 2.0, delta_time);
    render_frame();
    non_render_time = seconds_since_init();

    entity_frame_turnover();

    reset_temporary_storage();
    game_frame_count += 1;

    // doing this after game_frame_count advances so the data are correct for the next generation of entities
    // set_global_entities();

    new_time := seconds_since_init();
    delta_time = clamp((new_time - per_frame_time).(float32), 0.00001, 0.25);
    per_frame_time = new_time;
    if fixed_delta_time != 0.0 {
        delta_time = fixed_delta_time;
    }
    delta_time *= delta_time_multiplier;

    delta_times[dt_index] = delta_time;
    render_times[dt_index] = render_dt;
    simulation_times[dt_index] = simulation_dt;
    dt_index = increment_wrap(dt_index, 0, delta_times.count-1);

    #if BUILDVAR_DO_PROFILING {{
        scope_timer("make scope timer allocations");
        scope_timer_stack_diffs_this_frame := scope_timer_stack_diffs.count - previous_scope_timer_stack_diffs_count;
        scope_timer_stack_diffs_remaining := scope_timer_stack_diffs.allocated - scope_timer_stack_diffs.count;
        estimated_frames_before_allocation := scope_timer_stack_diffs_this_frame.(float64) / scope_timer_stack_diffs_remaining.(float64);
        if estimated_frames_before_allocation <= 10 {
            array_reserve(*scope_timer_stack_diffs, 2 * scope_timer_stack_diffs.count);
        }
        previous_scope_timer_stack_diffs_count = scope_timer_stack_diffs.count;
    }}
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

scope_timer :: ($name := "", is_game_frame_timer := false) #expand {
    #if BUILDVAR_DO_PROFILING {
        proc_name :: #procedure_name();
        timer_name :: #run ifx name == "" then tprint("%", proc_name) else tprint("% :: %", proc_name, name);
        id :: #run get_scope_timer_id();

        if is_profiling_on {
            if scope_timers.count <= id {
                array_resize(*scope_timers, id+1);
            }
            scope_timers[id].name = timer_name;
            new_stack_diff := Scope_Timer_Stack_Diff.{cpu_time=0,timer_id=id,is_scope_begin=true,is_game_frame=is_game_frame_timer};
            Win32.QueryPerformanceCounter(*new_stack_diff.cpu_time);
            array_add(*scope_timer_stack_diffs, new_stack_diff);
        }

        `defer {
            if is_profiling_on {
                new_stack_diff := Scope_Timer_Stack_Diff.{cpu_time=0,timer_id=id,is_scope_begin=false,is_game_frame=is_game_frame_timer};
                Win32.QueryPerformanceCounter(*new_stack_diff.cpu_time);
                array_add(*scope_timer_stack_diffs, new_stack_diff);
            }
        }
    }
}

report_scope_times :: () {
    #if BUILDVAR_DO_PROFILING {
        Timer_Tracker :: struct {
            cpu_time_deltas: [..]s64;
            frame_cpu_time_deltas: [..]s64;
            begin_cpu_time: s64;
            last_known_frame_begin_index: s32 = -1;
            scope_is_open: bool;
        };

        trackers: [..]Timer_Tracker;

        game_frame_began: bool;
        frame_began_at_index: s32;

        for scope_timer_stack_diffs {
            required_tracker_ct := it.timer_id + 1;
            if required_tracker_ct > trackers.count {
                array_resize(*trackers, required_tracker_ct);
                assert(it.is_scope_begin);
            }

            {
                using trackers[it.timer_id];

                if it.is_game_frame {
                    if it.is_scope_begin {
                        assert(!game_frame_began);
                        game_frame_began = true;
                        frame_began_at_index = xx it_index;
                    } else {
                        assert(game_frame_began);
                        game_frame_began = false;
                        array_add(*frame_cpu_time_deltas, 0);
                    }
                } else {
                    if last_known_frame_begin_index != frame_began_at_index {
                        array_add(*frame_cpu_time_deltas, 0);
                        last_known_frame_begin_index = frame_began_at_index;
                    }
                }

                if it.is_scope_begin {
                    assert(!scope_is_open);
                    scope_is_open = true;
                    begin_cpu_time = it.cpu_time;
                } else {
                    assert(scope_is_open);
                    scope_is_open = false;
                    time_delta := max(it.cpu_time - begin_cpu_time, 0);
                    array_add(*cpu_time_deltas, time_delta);
                    frame_cpu_time_deltas[frame_cpu_time_deltas.count-1] += time_delta;
                }
            }
        }
        array_reset(*scope_timer_stack_diffs);

        get_array_stats :: (arr: []s64, percentile := 0.99) -> (min: float64, median: float64, high_percentile: float64) {
            if arr.count < 3 {
                return 0,0,0;
            }
            quick_sort(arr, (a, b) => a - b);
            min_cpu_time := arr[0];
            median_cpu_time: s64;
            if arr.count & 0x1 == 0 {
                median_part_1 := arr[arr.count/2];
                median_part_2 := arr[arr.count/2+1];
                median_cpu_time = (median_part_1 + median_part_2) / 2;
            } else {
                median_cpu_time = arr[arr.count/2];
            }
            high_percentile_cpu_time_index : s64 = xx (arr.count.(float64) * percentile);
            high_percentile_cpu_time := arr[high_percentile_cpu_time_index];
            cpu_frequency_per_ms := cpu_frequency / 1000;
            inv_cpu_frequency_per_ms : float64 = (1.0).(float64) / cpu_frequency_per_ms.(float64);

            return min_cpu_time.(float64) * inv_cpu_frequency_per_ms,
                median_cpu_time.(float64) * inv_cpu_frequency_per_ms,
                high_percentile_cpu_time.(float64) * inv_cpu_frequency_per_ms;
        }

        for trackers {
            if it.cpu_time_deltas.count < 1 {
                continue;
            }
            log("[%]", scope_timers[it_index].name);
            scope_min, scope_median, scope_high_percentile := get_array_stats(it.cpu_time_deltas);
            frame_min, frame_median, frame_high_percentile := get_array_stats(it.frame_cpu_time_deltas);
            log(
#string HERE
    ---------    ------- --
    scope min    % ms
          med    % ms
          .99    % ms
    ---------    ------- --
    frame min    % ms
          med    % ms
          .99    % ms
    ---------    ------- --
HERE,
                FormatFloat.{value=scope_min, width=7, trailing_width=4},
                FormatFloat.{value=scope_median, width=7, trailing_width=4},
                FormatFloat.{value=scope_high_percentile, width=7, trailing_width=4},
                FormatFloat.{value=frame_min, width=7, trailing_width=4},
                FormatFloat.{value=frame_median, width=7, trailing_width=4},
                FormatFloat.{value=frame_high_percentile, width=7, trailing_width=4},
            );
        }
    }
}

Boot_Stage :: enum {
    STARTUP;
    SHUTDOWN;
}

fixed_delta_time := 0.0; @command_line
delta_time_multiplier := 1.0; @command_line

window: Window_Type;
console_window: Window_Type;
delta_time := 0.01;
game_frame_count: s32;
per_frame_time: float64;
non_render_time: float64;
cpu_frequency: s64;
quit := false;

profiling_on: bool; @command_line
profiling_off: bool; @command_line
is_profiling_on: bool;
profiling_started_at_time: float64;

simulation_dt: float;
render_dt: float;

DELTA_TIME_COUNT :: 120;
delta_times: [DELTA_TIME_COUNT]float32;
simulation_times: [DELTA_TIME_COUNT]float32;
render_times: [DELTA_TIME_COUNT]float32;
dt_index: s32;

breakpoint_switch_0: bool;
breakpoint_switch_9: bool;
breakpoint_switch_8: bool;
breakpoint_switch_7: bool;

switch_break :: (val := -1) {
    if (val == -1 || val == 0) && breakpoint_switch_0 {
        debug_break();
    } else if (val == -1 || val == 9) && breakpoint_switch_9 {
        debug_break();
    } else if (val == -1 || val == 8) && breakpoint_switch_8 {
        debug_break();
    } else if (val == -1 || val == 7) && breakpoint_switch_7 {
        debug_break();
    }
}

#import "Basic"()();
#import "String";
#import "Red_Mango_Core"()();
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
// #load "physics_properties.jai";
#load "input.jai";
#load "vulkan.jai";
#load "imgui/imgui_impl.jai";
#load "camera.jai";
#load "load_assets.jai";
#load "world.jai";
#load "scratch.jai";
#load "allocators.jai";
#load "physics_new.jai";
#load "draw.jai";
#load "raycast.jai";
#load "add_to_context.jai";
#load "collision.jai";
#load "collision_grid.jai";
#load "ai/ai.jai";
#load "think.jai";

#load "collision_types.jai";

#load "entities/entity.jai";
#load "entities/entity_control.jai";
#load "entities/spawn_entity.jai";
// #load "overlap.jai";

kernel32 :: #system_library "kernel32";
GetConsoleWindow :: () -> Win32.HWND #foreign kernel32;