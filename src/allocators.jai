
boot_allocators :: (stage: Boot_Stage) -> bool {
    if stage == .STARTUP {
        // init(*program_runtime_flat_pool);
        // program_runtime_allocator.proc = flat_pool_allocator_proc;
        // program_runtime_allocator.data = *program_runtime_flat_pool;
        bump_allocator_initialize(*program_runtime_allocator);
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

program_runtime_allocator: Bump_Allocator;
