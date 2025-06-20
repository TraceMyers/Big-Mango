
boot_allocators :: (stage: Boot_Stage) -> bool {
    if stage == .STARTUP {
        init(*program_runtime_flat_pool);
        program_runtime_allocator.proc = flat_pool_allocator_proc;
        program_runtime_allocator.data = *program_runtime_flat_pool;
        return true;
    } else {
        reset(*program_runtime_flat_pool, overwrite_memory=true);
        return true;
    }
}

program_runtime_flat_pool: Flat_Pool;
program_runtime_allocator: Allocator;;
