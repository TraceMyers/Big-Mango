Bound_Array :: struct($T: Type) {
    array: []T;
    max: s64;
}

bound_array :: inline (from_data: []$T) -> Bound_Array(T) {
    buf: Bound_Array(T) = ---;
    buf.array.data = from_data.data;
    buf.array.count = 0;
    buf.max = from_data.count;
    return buf;
}

bound_array_remove_at_swap :: inline (buf: *Bound_Array($T), i: s64) {
    assert(buf.array.count > 0);
    if i != buf.array.count-1 {
        buf.array[i] = buf.array[buf.array.count-1];
    }
    buf.array.count -= 1;
}

bound_array_add :: inline (buf: *Bound_Array($T)) -> *T {
    assert(buf.array.count + 1 <= buf.max);
    buf.array.count += 1;
    return *buf.array[buf.array.count-1];
}

bound_array_add :: inline (buf: *Bound_Array($T), item: T) {
    assert(buf.array.count + 1 <= buf.max);
    buf.array.count += 1;
    buf.array[buf.array.count-1] = item;
}

bound_array_append :: inline (buf: *Bound_Array($T), items: []T)  {
    assert(buf.array.count + items.count <= buf.max);
    copy_memory(buf.array.data+buf.array.count, items.data, items.count);
    buf.array.count += items.count;
}

bound_array_reset :: inline (buf: *Bound_Array($T), keep_data_reference := true) {
    if !keep_data_reference {
        buf.array.data = null;
        buf.max = 0;
    }
    buf.array.count = 0;
}

Bound_Local_Array :: struct($T: Type, $IN_MAX_COUNT: u64) {
    MAX_COUNT :: IN_MAX_COUNT;
    array : []T;
    array_data: [IN_MAX_COUNT]T;
}

bound_local_array_init :: inline (buf: *void) {
    buffer := buf.(*Bound_Local_Array(s32, 1));
    buffer.array.data = buffer.array_data.data;
    buffer.array.count = 0;
}

bound_local_array_add :: inline (buf: *Bound_Local_Array($T, $MAX_COUNT), item: T) {
    assert((buf.array.count + 1).(u64) <= MAX_COUNT);
    buf.array.count += 1;
    buf.array[buf.array.count-1] = item;
}

bound_local_array_append :: inline (buf: *Bound_Local_Array($T, $MAX_COUNT), items: []T)  {
    assert((buf.array.count + items.count).(u64) <= MAX_COUNT);
    copy_memory(buf.array.data+buf.array.count, items.data, items.count);
    buf.array.count += items.count;
}

copy_memory :: inline (dest: *$T, src: *T, count: s64) {
    memcpy(dest, src, count * size_of(T));
}

temp_dynamic_array :: inline ($T: Type, reserve_count := 0) -> [..]T {
    array: [..]T;
    array.allocator = temp;
    array_reserve(*array, reserve_count);
    return array;
}

alloc_array :: inline ($T: Type, count: s64, allocator:=context.allocator) -> []T {
    buffer: []T = ---;
    buffer.data = xx alloc(count * size_of(T),, allocator);
    buffer.count = count;
    return buffer;
}

array_element_index :: inline (array: []T, item: *$T) -> s64 {
    index := item - array.data;
    assert(index >= 0 && index < array.count);
    return index;
}

arrays_equal :: inline (a: []$T, b: []T) -> bool {
    if a.count != b.count return false;
    for a { 
        if it != b[it_index] then return false; 
    }
    return true;
}

array_append :: inline (a: *[..]$T, b: []T) {
    if b.count == 0 then return;
    prev_count := a.count;
    array_resize(a, a.count + b.count);
    copy_memory(a.data + prev_count, b.data, b.count);
}

concatenate :: (a: []$T, b: []T, allocator:=context.allocator) -> []T {
    arr := alloc_array(T, a.count + b.count, allocator);
    copy_memory(arr.data, a.data, a.count);
    copy_memory(arr.data + a.count, b.data, b.count);
    return arr;
}

duplicate :: (array: []$T, allocator:=context.allocator) -> []T {
    duplicate := alloc_array(T, array.count, allocator);
    copy_array(duplicate, array);
    return duplicate;
}

copy_array :: inline (dest: []$T, src: []T) {
    assert(dest.count >= src.count);
    copy_memory(dest.data, src.data, dest.count);
}

zero_array :: inline (array: []$T) {
    if array.count > 0 {
        zero_memory(array.data, array.count * size_of(T));
    }
}

zero_memory :: inline (data: *void, byte_count: s64) {
    memset(data, 0, byte_count);
}

resize_copy :: (array: *[]$T, new_count: s64) {
    new_array := alloc_array(T, new_count);
    copy_count := min(new_count, array.count);
    if copy_count > 0 {
        memcpy(new_array.data, array.data, copy_count * size_of(T));
    }
    array_reset(array);
    array.* = new_array;
}

copy_range_inside_array :: (array: []$T, dst: s64, src: s64, count: s64) {
    assert(count > 0 && dst != src);
    diff := dst - src;
    abs_diff := abs(diff);
    if abs_diff < count {
        if diff < 0 then for 0..count-1 {
            array[dst+it] = array[src+it];
        } else for #v2 < 0..count-1 {
            array[dst+it] = array[src+it];
        }
    } else {
        memcpy(array.data + dst, array.data + src, count * size_of(T));
    }
}

array_shrink :: (array: *[..]$T) {
    if array.allocated > array.count {
        new_allocation := alloc(array.count * size_of(T),, array.allocator);
        memcpy(new_allocation, array.data, array.count * size_of(T));
        {
            scope_set_allocator(array.allocator);
            free(array.data);
        }
        array.data = new_allocation;
        array.allocated = array.count;
    }
}

array_shrink_if_small_enough :: (array: *[..]$T, realloc_if_using_leq_proportion := 0.75) {
    if array.count < 8 && array.count != 0 {
        return;
    }
    if array.allocated == 0 {
        assert(array.data == null);
        assert(array.count == 0);
        return;
    }
    if array.count.(float) / array.allocated.(float) <= realloc_if_using_leq_proportion {
        array_shrink(array);
    }
}

// reset a dynamic array without freeing the allocation. unlike array_reset_keeping_memory in that the allocation is not kept
reset_without_free :: (arr: *[..]$T) {
    arr.data = null;
    arr.count = 0;
    arr.allocated = 0;
    arr.allocator = context.default_allocator;
}

reset_without_free :: (str: *string) {
    str.data = null;
    str.count = 0;
}

// dst: |-----|
// src:    |-----|

// dst:    |-----|
// src: |-----|

