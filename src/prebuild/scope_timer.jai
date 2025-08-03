
Scope_Timer :: struct {
    name: string;
}

Scope_Timer_Stack_Diff :: struct {
    cpu_time: s64;
    timer_id: u32;
    is_scope_begin: bool;
    is_game_frame: bool;
}

// todo: should be able to start/stop profiling, which means there should be multiple profiling sessions.
// todo: per-thread stack diff arrays.
scope_timers: [..]Scope_Timer;
scope_timer_stack_diffs: [..]Scope_Timer_Stack_Diff;
previous_scope_timer_stack_diffs_count: s64;

#import "Basic";