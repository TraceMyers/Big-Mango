boot_allocators :: (stage: Boot_Stage) -> bool {

    if stage == .STARTUP {
        // init(*program_runtime_flat_pool);
        // program_runtime_allocator.proc = flat_pool_allocator_proc;
        // program_runtime_allocator.data = *program_runtime_flat_pool;
        return true;
    } else {
        // reset(*program_runtime_flat_pool, overwrite_memory=true);
        return true;
    }
}

program_runtime_reserve :: (array: *[..]$T, count: s64) {
    assert(array.data == null && array.count == 0 && array.allocated == 0);
    array.allocator = program_runtime_allocator;
    array_reserve(array, count);
    array.allocator = no_allocator;
}

program_runtime_initialize :: (allocator: *Nesting_Allocator($C), chunk_list_size: s64, all_data_size: s64) {
    chunk_list_count := div_ceil(all_data_size, chunk_list_size);
    initialize_nesting_allocator(allocator, program_runtime_allocator, chunk_list_size, chunk_list_count);
    allocator.parent_allocator = no_allocator;
}

program_runtime_initialize :: (pool: *Pool($T), count: s64) {
    scope_set_allocator(program_runtime_allocator);
    set_capacity(pool, count);
    lock_allocation(pool);
}

program_runtime_allocate :: (array: *[]$T, count: s64) {
    array.* = alloc_array(T, count, program_runtime_allocator);
}

program_runtime_allocator: Bump_Allocator;
