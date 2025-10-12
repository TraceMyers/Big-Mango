
BUMP_ALLOCATOR_DEFAULT_HEAP_SIZE : s32 : 16 * 1024 * 1024; // 16MB

Bump_Allocator :: struct {
    using #as base: Allocator;
    parent_allocator: Allocator;
    heap: Bump_Allocator_Heap;
}

Bump_Allocator_Heap :: struct {
    bytes: []u8;
    end: s32;
}

bump_allocator_initialize :: (using bump: *Bump_Allocator, in_parent_allocator := context.default_allocator, heaps_tracking_array_ct := 32, in_heap_size := BUMP_ALLOCATOR_DEFAULT_HEAP_SIZE) {
    parent_allocator = in_parent_allocator;
    scope_set_allocator(parent_allocator);
    assert(in_heap_size > 0);
    in_heap_size = ceil_to_pow2_multiple(in_heap_size, 8);
    proc = bump_allocator_proc;
    data = bump;
    heap = .{};
    heap.bytes = alloc_array(u8, in_heap_size, parent_allocator);
}

bump_allocator_proc :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, allocator_data: *void) -> *void {
    if mode == {
    case .ALLOCATE;
        return bump_allocator_allocate(xx allocator_data, size);
    case .RESIZE;
        return bump_allocator_resize(xx allocator_data, size, old_size, old_memory);
    case .FREE;
        // could be useful for debug
    case .CREATE_HEAP;
        // bump_allocator_initialize(xx allocator_data);
    case .DESTROY_HEAP;
        bump_allocator_reset(xx allocator_data, false);
    }
    return null;
}

bump_allocator_allocate :: (using bump: *Bump_Allocator, size: s64) -> *void {
    new_size := heap.end + size;
    assert(new_size <= heap.bytes.count);
    data_out := *heap.bytes[heap.end];
    memset(data_out, 0, size);
    // align everything to 8 because it's easy and works fine I think
    heap.end += xx size;
    heap.end = ceil_to_pow2_multiple(heap.end, 8);

    return data_out;
}

bump_allocator_resize :: (using bump: *Bump_Allocator, size: s64, old_size: s64, old_memory: *void) -> *void {
    if size <= old_size {
        return old_memory;
    }
    new_memory := bump_allocator_allocate(bump, size);
    memcpy(new_memory, old_memory, old_size);
    return new_memory;
}

bump_allocator_reset :: (using bump: *Bump_Allocator, keep_memory := true) {
    if keep_memory {
        heap.end = 0;
    } else {
        scope_set_allocator(parent_allocator);
        if heap.bytes.count > 0 {
            free(heap.bytes.data);
        }
        bump.* = .{};
    }
}

get_high_water_mark :: (using bump: *Bump_Allocator) -> s32 {
    return heap.end;
}

reset_to_high_water_mark :: (using bump: *Bump_Allocator, mark: s32) {
    assert(heap.bytes.count >= mark);
    heap.end = mark;
}
