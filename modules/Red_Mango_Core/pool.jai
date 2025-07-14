Pool_Resize_Behavior :: enum {
    DEFAULT;
    ALLOW;
    DISALLOW;
}

Pool :: struct($Item_Type: Type) {
    items: [..]Item_Type;
    in_use: Bit_Array(1);
    top := -1;
    shrink_to_min : s32 = 0;
    allow_grow_default := true;
    allow_shrink_default := true;
}

set_capacity :: (using pool: *Pool($T), cap: s64) {
    array_resize(*items, cap);
    set_capacity(*in_use, cap);    
}

lock_allocation :: (using pool: *Pool($T)) {
    items.allocator = no_allocator;
    in_use.items.allocator = no_allocator;
    allow_grow_default = false;
    allow_shrink_default = false;
}

reset :: (using pool: *Pool($T), deinit_item_proc: (*T) = null, keep_memory := false) {
    if in_use.items.count > 0 {
        assert(items.count <= get_group_count(*in_use));
        for 0..items.count-1 {
            if bit_is_set(*in_use, it) {
                deinit_item_proc(*items[it]);
            }
        }
        reset(*in_use, keep_memory);
        if keep_memory {
            array_reset_keeping_memory(*items);
        } else {
            array_reset(*items);
        }
    } else {
        assert(items.count == 0);
    }

    top = -1;
}

request_item :: no_inline (using pool: *Pool($T), init_item_proc: (*T) = null, grow_behavior := Pool_Resize_Behavior.DEFAULT) -> s64 {
    index := find_first_unset_bit(*in_use);
    if index != -1 {
        set_bit(*in_use, index);
        if index > top then top = index;
        if init_item_proc then init_item_proc(*items[index]);
        return index;
    }

    do_allow_grow := ifx grow_behavior == .DEFAULT then allow_grow_default else grow_behavior == .ALLOW;
    if !do_allow_grow {
        return -1;
    }

    index = items.count;
    top = items.count;

    new_item_count := items.count + 16;
    array_resize(*items, new_item_count);
    set_capacity(*in_use, new_item_count);
    set_bit(*in_use, index);
    if init_item_proc then init_item_proc(*items[index]);

    return index;
}

return_item :: (using pool: *Pool($T), i: s64, deinit_item_proc: (*T) = null, shrink_behavior := Pool_Resize_Behavior.DEFAULT) {
    if deinit_item_proc then deinit_item_proc(*items[i]);

    unset_bit(*in_use, i);

    if i == top {
        top = find_last_set_bit(*in_use);
        do_allow_shrink := ifx shrink_behavior == .DEFAULT 
            then allow_shrink_default 
            else shrink_behavior == .ALLOW;

        if do_allow_shrink && items.count > shrink_to_min {
            required_count := top + 1;
            required_count = max(required_count, shrink_to_min);
            if required_count >= items.count then return;

            // div by 2 repeatedly until we find the threshold we're under
            test_threshold := items.count >> 1;
            while required_count < test_threshold {
                test_threshold >>= 1;
            }

            // only shrink by up to half the space we could shrink, to leave room for incoming adds
            test_threshold <<= 1;
            if test_threshold >= items.count then return;

            new_count := max(test_threshold, shrink_to_min);
            array_resize(*items, new_count);
            set_capacity(*in_use, new_count);
        }
    }
}

operator *[] :: inline (using pool: *Pool($T), i: s64) -> *T {
    assert(bit_is_set(*in_use, i));
    return *items[i];
}

get_item :: inline (using pool: *Pool($T), i: s64) -> *T {
    return *items[i];
}

find_item :: (using pool: *Pool($T1), user_data: $T2, compare_proc: (*T1, T2) -> bool) -> s64 {
    i := -1;
    
    while true {
        pre_iter_i := i;
        i = find_first_set_bit(*in_use, -1, i+1);
        if i == -1 then break;
        if compare_proc(*items[i], user_data) then return i;
        if i == pre_iter_i then i += 1;
    }
    return -1;
}

get_item_index :: (using pool: *Pool($T), item: *T) -> s64 {
    i := item - items.data;
    if i < 0 || i > items.count {
        return -1;
    }
    return i;
}

is_empty :: inline (using pool: *Pool($T)) -> bool {
    return top == -1;
}

is_item_in_use :: inline (using pool: *Pool($T), i: s64) -> bool {
    return bit_is_set(*in_use, i);
}
