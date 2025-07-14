
BUMP_ALLOCATOR_DEFAULT_HEAP_SIZE : s32 : 16 * 1024 * 1024; // 16MB

Bump_Allocator :: struct {
    using #as base: Allocator;
    heaps: [..]Bump_Allocator_Heap;
    heap_index: s32;
    default_heap_size: s32;
}

Bump_Allocator_Heap :: struct {
    bytes: []u8;
    end: s32;
}

Bump_Allocator_High_Water_Mark :: struct {
    heap_index: s32;
    heap_end: s32;
}

bump_allocator_initialize :: (using bump: *Bump_Allocator, heaps_tracking_array_ct := 32, in_default_heap_size := BUMP_ALLOCATOR_DEFAULT_HEAP_SIZE) {
    scope_set_allocator(context.default_allocator);
    assert(in_default_heap_size > 0);
    assert(heaps.count == 0);
    assert(heap_index == 0);
    in_default_heap_size = ceil_to_pow2_multiple(in_default_heap_size, 8);
    proc = bump_allocator_proc;
    data = bump;
    array_resize(*heaps, heaps_tracking_array_ct);
    heaps[0].bytes = alloc_array(u8, in_default_heap_size);
    default_heap_size = in_default_heap_size;
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
    scope_set_allocator(context.default_allocator);
    cur_heap := *heaps[heap_index];
    new_size := cur_heap.end + size;
    if new_size > cur_heap.bytes.count {
        heap_index += 1;
        if heap_index >= heaps.count {
            assert(heap_index == heaps.count);
            _ = array_add(*heaps);
        }
        assert(heaps[heap_index].end == 0);
        if heaps[heap_index].bytes.count == 0 {
            alloc_size := max(size * 2, default_heap_size);
            heaps[heap_index].bytes = alloc_array(u8, alloc_size);
        }
        cur_heap = *heaps[heap_index];
    }

    data_out := *cur_heap.bytes[cur_heap.end];
    memset(data_out, 0, size);
    // align everything to 8 because it's easy and works fine I think
    cur_heap.end += xx size;
    cur_heap.end = ceil_to_pow2_multiple(cur_heap.end, 8);

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
        heap_index = 0;
        for *heaps {
            it.end = 0;
        }
    } else {
        scope_set_allocator(context.default_allocator);
        for *heaps {
            if it.bytes.count > 0 {
                free(it.bytes.data);
            }
        }
        array_reset(*heaps);
        bump.* = .{};
    }
}

get_high_water_mark :: (using bump: *Bump_Allocator) -> Bump_Allocator_High_Water_Mark {
    return .{heap_index, heaps[heap_index].end};
}

reset_to_high_water_mark :: (using bump: *Bump_Allocator, mark: Bump_Allocator_High_Water_Mark) {
    assert(mark.heap_index < heaps.count);
    assert(mark.heap_index <= heap_index, "mark index: %, heap index: %", mark.heap_index, heap_index);
    assert(heaps[mark.heap_index].bytes.count >= mark.heap_end);
    if mark.heap_index < heap_index {
        for mark.heap_index+1..heap_index {
            heaps[it].end = 0;
        }
    }
    heap_index = mark.heap_index;
    heaps[heap_index].end = mark.heap_end;
}
