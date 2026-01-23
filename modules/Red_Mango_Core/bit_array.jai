
Bit_Array :: struct($IN_GROUP_BIT_COUNT: int) {
    #run,stallable assert(is_power_of_two(IN_GROUP_BIT_COUNT) && IN_GROUP_BIT_COUNT <= 64);
    items: [..]u64;
    groups_bit_size: s32;
    GROUP_BIT_COUNT :: IN_GROUP_BIT_COUNT;
    GROUPS_PER_U64 :: 64 / GROUP_BIT_COUNT;
    GROUP_INDEXING_SHIFT :: #run,stallable _bit_scan_forward(GROUPS_PER_U64) - 1;
    GROUP_BASE_MASK :: #run,stallable bit_array_group_base_mask(IN_GROUP_BIT_COUNT);
}

set_capacity :: inline (using array: *Bit_Array($COUNT), in_group_count: s64) {
    groups_bit_size = xx (in_group_count * GROUP_BIT_COUNT);
    items_count := div_ceil(in_group_count, GROUPS_PER_U64);
    array_resize(*items, items_count);
}

add_bit_set :: (using array: *Bit_Array($COUNT)) {
    _ := array_add(*items);
    groups_bit_size = items.count * GROUPS_PER_U64;
}

bit_array_group_base_mask :: inline (bit_group_count: int) -> u64  {
    return ifx bit_group_count == 64 then (~0).(u64) else ((1 << bit_group_count) - 1).(u64,force);
}

get_group_count :: inline (using array: *Bit_Array($COUNT)) -> s64 {
    return groups_bit_size / GROUP_BIT_COUNT;
}

get_count :: get_group_count;

single_bit_mask :: inline (using array: *Bit_Array($COUNT), group: s64, in_group_index: s64) -> s64, u64 {
    assert(group < get_group_count(array));
    assert(in_group_index >= 0 && in_group_index <= GROUP_BIT_COUNT);
    items_index := group >> GROUP_INDEXING_SHIFT;
    truncated_group_index := items_index << GROUP_INDEXING_SHIFT;
    group_index_in_u64 := group - truncated_group_index;
    bit_mask := (1 << (group_index_in_u64 * GROUP_BIT_COUNT + in_group_index)).(u64,no_check);
    return items_index, bit_mask;
}

group_bit_mask :: inline (using array: *Bit_Array($COUNT), group: s64) -> s64, u64 {
    assert(group < get_group_count(array));
    items_index := group >> GROUP_INDEXING_SHIFT;
    truncated_group_index := items_index << GROUP_INDEXING_SHIFT;
    group_index_in_u64 := group - truncated_group_index;
    return items_index, GROUP_BASE_MASK << (group_index_in_u64 * GROUP_BIT_COUNT);
}

set_bit :: inline (using array: *Bit_Array($COUNT), group: s64, in_group_index := 0) {
    assert(group < get_group_count(array));
    index, mask := single_bit_mask(array, group, in_group_index);
    items[index] |= mask;
}

unset_bit :: inline (using array: *Bit_Array($COUNT), group: s64, in_group_index := 0) {
    assert(group < get_group_count(array));
    index, mask := single_bit_mask(array, group, in_group_index);
    items[index] &= ~mask;
}

bit_is_set :: inline (using array: *Bit_Array($COUNT), group: s64, in_group_index := 0) -> bool {
    assert(group < get_group_count(array));
    index, mask := single_bit_mask(array, group, in_group_index);
    return (items[index] & mask) != 0;
}

set_bit_group :: inline (using array: *Bit_Array($COUNT), group: s64) {
    assert(group < get_group_count(array));
    index, mask := group_bit_mask(array, group);
    items[index] |= mask;
}

unset_bit_group :: inline (using array: *Bit_Array($COUNT), group: s64) {
    assert(group < get_group_count(array));
    index, mask := group_bit_mask(array, group);
    items[index] &= ~mask;
}

any_bits_in_group_set :: inline (using array: *Bit_Array($COUNT), group: s64) -> bool {
    assert(group < get_group_count(array));
    index, mask := group_bit_mask(array, group);
    return (items[index] & mask) != 0;
}

all_bits_in_group_set :: inline (using array: *Bit_Array($COUNT), group: s64) -> bool {
    assert(group < get_group_count(array));
    index, mask := group_bit_mask(array, group);
    return (items[index] & mask) == mask;
}

set_all :: inline (using array: *Bit_Array($COUNT)) {
    if items.count > 0 {
        memset(items.data, 0xff, items.count * size_of(u64));
    }
}

unset_all :: inline (using array: *Bit_Array($COUNT)) {
    if items.count > 0 {
        memset(items.data, 0x00, items.count * size_of(u64));
    }
}

reset :: inline (using array: *Bit_Array($COUNT), keep_memory := false) {
    if keep_memory {
        array_reset_keeping_memory(*items);
    } else {
        array_reset(*items);
    }
}

// if in_group_index == -1, search for a group with any unset bits. else, search for a group with a bit unset at in_group_index
find_first_group_with_unset_bits :: (using array: *Bit_Array($COUNT), in_group_index := -1, start_group := 0, $ENFORCE_BITS_PER_GROUP:s64=0) -> group: s64 {
    // couldn't get modify to work for this
    #if ENFORCE_BITS_PER_GROUP != 0 {
        assert(ENFORCE_BITS_PER_GROUP == COUNT); 
    }
    start_item := start_group >> GROUP_INDEXING_SHIFT;
    start_group_in_item := start_group - (start_item << GROUP_INDEXING_SHIFT);
    if start_item >= items.count || start_item < 0 {
        return -1;
    }

    // the ability to start scanning from a specific group index adds significant complication in order
    // to keep this function as performant as possible for large data.
    // the first part here is checking to see if the first bit collection, excluding ignored groups at the
    // beginning, has the kind of gap that is being searched for

    ignore_groups_mask : u64 = 0;
    if start_group_in_item > 0 then for 0..start_group_in_item-1 {
        ignore_groups_mask |= GROUP_BASE_MASK << (it * GROUP_BIT_COUNT);
    }

    ref_mask, collection_mask := make_search_masks(array, in_group_index);

    first_bit_collection_with_ignored_groups := items[start_item] | ignore_groups_mask;
    if (first_bit_collection_with_ignored_groups & collection_mask) != collection_mask {
        #if GROUPS_PER_U64 == 64 {
            return_group_index_1_bit_groups(get_group_count(array), first_bit_collection_with_ignored_groups, start_item, true, true);
        } else {
            return_group_index_n_bit_groups(GROUPS_PER_U64, GROUP_BIT_COUNT, get_group_count(array), first_bit_collection_with_ignored_groups, start_item, ref_mask, true, true);;
        }
    }

    // after searching the first bit collection, it gets simpler to search the rest, because there are
    // no more ignored groups.

    iter_ct := items.count - start_item;
    if iter_ct > 1 {
        #if GROUPS_PER_U64 == 64 {
            for i: start_item+1..items.count-1 {
                bit_collection := items[i];
                if bit_collection == 0xffff_ffff_ffff_ffff {
                    continue;
                }
                return_group_index_1_bit_groups(get_group_count(array), bit_collection, i, true, true);
            }
        } else {
            for i: start_item+1..items.count-1 {
                bit_collection := items[i];
                if (bit_collection & collection_mask) == collection_mask {
                    continue;
                }
                return_group_index_n_bit_groups(GROUPS_PER_U64, GROUP_BIT_COUNT, get_group_count(array), bit_collection, i, ref_mask, true, true);
            }
        }
    }
    return -1;
}
find_first_unset_bit :: #bake_arguments find_first_group_with_unset_bits(ENFORCE_BITS_PER_GROUP=1);

// see comments in the forward search proc for some detail
find_last_group_with_unset_bits :: (using array: *Bit_Array($COUNT), in_group_index := -1, start_group := -1, $ENFORCE_BITS_PER_GROUP:=0) -> group: s64 {
    // couldn't get modify to work for this
    #if ENFORCE_BITS_PER_GROUP != 0 {
        assert(ENFORCE_BITS_PER_GROUP == COUNT); 
    }
    if start_group == -1 {
        start_group = get_group_count(array) - 1;
    }
    start_item := start_group >> GROUP_INDEXING_SHIFT;
    start_group_in_item := start_group - (start_item << GROUP_INDEXING_SHIFT);
    if start_item >= items.count || start_item < 0 {
        return -1;
    }

    ignore_groups_mask : u64 = 0;
    if start_group_in_item < (GROUPS_PER_U64 - 1) then for < start_group_in_item+1..GROUPS_PER_U64-1 {
        ignore_groups_mask |= GROUP_BASE_MASK << (it * GROUP_BIT_COUNT);
    }

    ref_mask, collection_mask := make_search_masks(array, in_group_index);

    first_bit_collection_with_ignored_groups := items[start_item] | ignore_groups_mask;
    if (first_bit_collection_with_ignored_groups & collection_mask) != collection_mask {
        #if GROUPS_PER_U64 == 64 {
            return_group_index_1_bit_groups(get_group_count(array), first_bit_collection_with_ignored_groups, start_item, false, true);
        } else {
            return_group_index_n_bit_groups(GROUPS_PER_U64, GROUP_BIT_COUNT, get_group_count(array), first_bit_collection_with_ignored_groups, start_item, ref_mask, false, true);;
        }
    }

    iter_ct := start_item + 1;
    if iter_ct > 1 {
        #if GROUPS_PER_U64 == 64 {
            for < i: 0..start_item-1 {
                bit_collection := items[i];
                if bit_collection == 0xffff_ffff_ffff_ffff {
                    continue;
                }
                return_group_index_1_bit_groups(get_group_count(array), bit_collection, i, false, true);
            }
        } else {
            for < i: 0..start_item-1 {
                bit_collection := items[i];
                if (bit_collection & collection_mask) == collection_mask {
                    continue;
                }
                return_group_index_n_bit_groups(GROUPS_PER_U64, GROUP_BIT_COUNT, get_group_count(array), bit_collection, i, ref_mask, false, true);
            }
        }
    }
    return -1;
}
find_last_unset_bit :: #bake_arguments find_last_group_with_unset_bits(ENFORCE_BITS_PER_GROUP=1);

find_last_group_with_set_bits :: (using array: *Bit_Array($COUNT), in_group_index := -1, start_group := -1, $ENFORCE_BITS_PER_GROUP:=0) -> group: s64 {
    // couldn't get modify to work for this
    #if ENFORCE_BITS_PER_GROUP != 0 {
        assert(ENFORCE_BITS_PER_GROUP == COUNT); 
    }
    if start_group == -1 {
        start_group = get_group_count(array) - 1;
    }
    start_item := start_group >> GROUP_INDEXING_SHIFT;
    start_group_in_item := start_group - (start_item << GROUP_INDEXING_SHIFT);
    if start_item >= items.count || start_item < 0 {
        return -1;
    }

    ignore_groups_mask : u64 = 0;
    if start_group_in_item < (GROUPS_PER_U64 - 1) then for < start_group_in_item+1..GROUPS_PER_U64-1 {
        ignore_groups_mask |= GROUP_BASE_MASK << (it * GROUP_BIT_COUNT);
    }
    ignore_groups_mask = ~ignore_groups_mask;

    ref_mask, collection_mask := make_search_masks(array, in_group_index);

    first_bit_collection_with_ignored_groups := items[start_item] & ignore_groups_mask;
    if (first_bit_collection_with_ignored_groups & collection_mask) != 0 {
        #if GROUPS_PER_U64 == 64 {
            return_group_index_1_bit_groups(get_group_count(array), first_bit_collection_with_ignored_groups, start_item, false, false);
        } else {
            return_group_index_n_bit_groups(GROUPS_PER_U64, GROUP_BIT_COUNT, get_group_count(array), first_bit_collection_with_ignored_groups, start_item, ref_mask, false, false);
        }
    }

    iter_ct := start_item + 1;
    if iter_ct > 1 {
        #if GROUPS_PER_U64 == 64 {
            for < i: 0..start_item-1 {
                bit_collection := items[i];
                if bit_collection == 0 {
                    continue;
                }
                return_group_index_1_bit_groups(get_group_count(array), bit_collection, i, false, false);
            }
        } else {
            for < i: 0..start_item-1 {
                bit_collection := items[i];
                if (bit_collection & collection_mask) == 0 {
                    continue;
                }
                return_group_index_n_bit_groups(GROUPS_PER_U64, GROUP_BIT_COUNT, get_group_count(array), bit_collection, i, ref_mask, false, false);
            }
        }
    }
    return -1;
}
find_last_set_bit :: #bake_arguments find_last_group_with_set_bits(ENFORCE_BITS_PER_GROUP=1);

find_first_group_with_set_bits :: (using array: *Bit_Array($COUNT), in_group_index := -1, start_group := 0, $ENFORCE_BITS_PER_GROUP:=0) -> group: s64 {
    // couldn't get modify to work for this
    #if ENFORCE_BITS_PER_GROUP != 0 {
        assert(ENFORCE_BITS_PER_GROUP == COUNT); 
    }
    start_item := start_group >> GROUP_INDEXING_SHIFT;
    start_group_in_item := start_group - (start_item << GROUP_INDEXING_SHIFT);
    if start_item >= items.count || start_item < 0 {
        return -1;
    }

    ignore_groups_mask : u64 = 0;
    if start_group_in_item > 0 then for 0..start_group_in_item-1 {
        ignore_groups_mask |= GROUP_BASE_MASK << (it * GROUP_BIT_COUNT);
    }
    ignore_groups_mask = ~ignore_groups_mask;

    ref_mask, collection_mask := make_search_masks(array, in_group_index);

    first_bit_collection_with_ignored_groups := items[start_item] & ignore_groups_mask;
    if (first_bit_collection_with_ignored_groups & collection_mask) != 0 {
        #if GROUPS_PER_U64 == 64 {
            return_group_index_1_bit_groups(get_group_count(array), first_bit_collection_with_ignored_groups, start_item, true, false);
        } else {
            return_group_index_n_bit_groups(GROUPS_PER_U64, GROUP_BIT_COUNT, get_group_count(array), first_bit_collection_with_ignored_groups, start_item, ref_mask, true, false);
        }
    }

    iter_ct := items.count - start_item;
    if iter_ct > 1 {
        #if GROUPS_PER_U64 == 64 {
            for i: start_item+1..items.count-1 {
                bit_collection := items[i];
                if bit_collection == 0 {
                    continue;
                }
                return_group_index_1_bit_groups(get_group_count(array), bit_collection, i, true, false);
            }
        } else {
            for i: start_item+1..items.count-1 {
                bit_collection := items[i];
                if (bit_collection & collection_mask) == 0 {
                    continue;
                }
                return_group_index_n_bit_groups(GROUPS_PER_U64, GROUP_BIT_COUNT, get_group_count(array), bit_collection, i, ref_mask, true, false);
            }
        }
    }
    return -1;
}
find_first_set_bit :: #bake_arguments find_first_group_with_set_bits(ENFORCE_BITS_PER_GROUP=1);

group_to_bit_index :: inline (using array: *Bit_Array($COUNT), group: s64, in_group_index := 0) -> s64 {
    return group * GROUP_BIT_COUNT + in_group_index;
}

// needed to bring this in from Bit_Operations module, and make it *not* a macro, otherwise crash when using at compile time. not clear why.
_bit_scan_forward :: inline (input: $T) -> s32 {  // One plus the index of the first bit, when searching from LSB to MSB. A result of 0 means the input was 0.
    BITS :: size_of(T)*8;
    #if CPU == .X64 {
        #if BITS == 8 {  // There's no bsf for 8 bits. Sad.
            result: s16 = -1;
            #asm {
                movzxbw   temp:, input;
                bsf.16    result, temp;
            }
        } else {
            result: T = xx,no_check -1;
            #asm {
                bsf?T     result, input;
            }
        }
        return (result + 1).(s32,trunc);
    } else {
        // @Speed: Slow fallback for other CPUs.
        for i: 0..BITS-1 {
            if input & cast,no_check(T) (1 << i) return (i + 1).(s32);
        }
        return 0;
    }
}

// ---------------------------------------------------------------------------------------------------------------------
#scope_file // ---------------------------------------------------------------------------------------------- SCOPE_FILE
// ---------------------------------------------------------------------------------------------------------------------

make_search_masks :: inline (using array: *Bit_Array($COUNT), in_group_index: s64) -> ref_mask: u64, collection_mask: u64 {
    ref_mask, collection_mask: u64 = ---;
    #if GROUPS_PER_U64 == 64 {
        collection_mask = 0xffff_ffff_ffff_ffff;
    } else {
        if in_group_index == -1 {
            ref_mask = GROUP_BASE_MASK;
            collection_mask = 0xffff_ffff_ffff_ffff;
        } else {
            _, ref_mask = single_bit_mask(array, 0, in_group_index);
            collection_mask = 0;
            for g: 0..GROUPS_PER_U64-1 {
                collection_mask |= ref_mask << (GROUP_BIT_COUNT * g);
            }
        }
    }
    return ref_mask, collection_mask;
}

return_group_index_1_bit_groups :: (in_group_count: s64, bit_collection: u64, collection_index: s64, $SEARCH_FORWARD: bool, $FINDING_GAP: bool) -> s64 #expand {
    #if SEARCH_FORWARD {
        #if FINDING_GAP {
            bit_index := ifx bit_collection == 0 then 0 else (_bit_scan_forward(~bit_collection) - 1).(s64);
        } else {
            bit_index := ifx bit_collection == 0 then 0 else (_bit_scan_forward(bit_collection) - 1).(s64);
        }
    } else {
        #if FINDING_GAP {
            bit_index := ifx bit_collection == 0 then 0 else (_bit_scan_reverse(~bit_collection) - 1).(s64);
        } else {
            bit_index := ifx bit_collection == 0 then 0 else (_bit_scan_reverse(bit_collection) - 1).(s64);
        }
    }
    group_index := collection_index * 64 + bit_index;
    `return ifx group_index >= in_group_count then -1 else group_index;
}

return_group_index_n_bit_groups :: (groups_per_u64: s64, group_bit_count: s64, in_group_count: s64, bit_collection: u64, collection_index: s64, mask: u64, $SEARCH_FORWARD: bool, $FINDING_GAP: bool) -> s64 #expand {
    #if SEARCH_FORWARD {
        for g: 0..groups_per_u64-1 {
            #if FINDING_GAP {
                match := (bit_collection & mask) != mask;
            } else {
                match := (bit_collection & mask) != 0;
            }
            if match {
                group_index := collection_index * groups_per_u64 + g;
                `return ifx group_index >= in_group_count then -1 else group_index;
            }
            mask <<= group_bit_count;
        }
    } else {
        for < g: 0..groups_per_u64-1 {
            reverse_search_mask := mask << (group_bit_count * g);
            #if FINDING_GAP {
                match := (bit_collection & reverse_search_mask) != reverse_search_mask;
            } else {
                match := (bit_collection & reverse_search_mask) != 0;
            }
            if match {
                group_index := collection_index * groups_per_u64 + g;
                `return ifx group_index >= in_group_count then -1 else group_index;
            }
        }
    }
    assert(false, tprint("failed to find a group with an unset bit even though the reference mask indicated it should exist. bit collection: 0x%, ref mask: %, u64 mask: %", _fib16(bit_collection,16), _fib16(`ref_mask,16), _fib16(`collection_mask,16)));
}


// tbh I just copied this because I had to copy the other one and I only need the two from the module.
_bit_scan_reverse :: inline (input: $T) -> s32 #expand {  // One plus the index of the first bit, when searching from MSB to LSB. A result of 0 means the input was 0.
    BITS :: size_of(T)*8;

    #if CPU == .X64 {
        #if BITS == 8 {
            result: s16 = -1;
            #asm {
                movzxbw   temp:, input;
                bsr.16    result, temp;
            }
        } else {
            result: T = xx,no_check -1;
            #asm {
                bsr?T     result, input;
            }
        }

        return cast,trunc(s32)(result + 1);
    } else {
        // @Speed: Slow fallback for other CPUs.
        for <i: 0..BITS-1 {
            if input & cast,no_check(T) (1 << i) return cast(s32) (i + 1);
        }

        return 0;
    }
}
