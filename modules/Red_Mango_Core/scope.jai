
scope_set_allocator :: (allocator: Allocator) #expand {
    _save_allocator := context.allocator;
    context.allocator = allocator;
    `defer context.allocator = _save_allocator;
}

scope_lock_mutex :: (mutex: *Mutex) #expand {
    lock(mutex);
    `defer unlock(mutex);
}

scope_set_working_directory :: (dir: string) #expand {
    cwd := get_working_directory();
    set_working_directory(dir);
    `defer set_working_directory(cwd);   
}

scope_mark_and_recede_allocations :: (using bump: *Bump_Allocator) #expand {
    mark := get_high_water_mark(bump);
    `defer reset_to_high_water_mark(bump, mark);
}
