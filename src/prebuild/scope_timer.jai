
Scope_Timer :: struct {
    name: string;
}

Scope_Timer_Stack_Diff :: struct {
    cpu_time: s64;
    timer_id: u32;
    is_scope_begin: bool;
    is_program_frame: bool;
}

get_scope_timer_id :: () -> u32 {
    out_id := atomic_add(*comptime_scope_id_counter, 1);
    return out_id;
}

// todo: per-thread stack diff arrays.
scope_timers: [..]Scope_Timer;
scope_timer_stack_diffs: [..]Scope_Timer_Stack_Diff;
previous_scope_timer_stack_diffs_count: s64;
comptime_scope_id_counter: u32;

#import "Basic";