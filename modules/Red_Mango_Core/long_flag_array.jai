
// maybe add some overhead to flag usage, but it's convenient for making one big flag set.

Long_Flag_Array_Indexer :: struct {
    index: s16;
    bit: s16;
}

Long_Flag_Array :: struct($Enum_Type: Type) {
    FLAG_COUNT :: #run enum_highest_value(Enum_Type) + 1;
    flag_sets: [#run div_ceil(FLAG_COUNT, 8)]u8;
}

convert_to_lfa_indexer :: inline (int_val: s32) -> Long_Flag_Array_Indexer {
    return .{xx ((int_val & ~0x07) >> 3), xx (int_val & 0x07)};
}

is_set :: inline (arr: *Long_Flag_Array($T), enum_val: T) -> bool {
    indexer := convert_to_lfa_indexer(xx enum_val);
    return (arr.flag_sets[indexer.index] & ((1).(u8) << indexer.bit)) != 0;
}

set :: inline (arr: *Long_Flag_Array($T), enum_val: T) {
    indexer := convert_to_lfa_indexer(xx enum_val);
    arr.flag_sets[indexer.index] |= ((1).(u8) << indexer.bit);
}

unset :: inline (arr: *Long_Flag_Array($T), enum_val: T) {
    indexer := convert_to_lfa_indexer(xx enum_val);
    arr.flag_sets[indexer.index] &= ~((1).(u8) << indexer.bit);
}

set_multiple :: inline (arr: *Long_Flag_Array($T), enum_vals: []T) {
    for enum_vals {
        set(arr, it);
    }
}

unset_multiple :: inline (arr: *Long_Flag_Array($T), enum_vals: []T) {
    for enum_vals {
        unset(arr, it);
    }
}

are_all_set :: inline (array: *Long_Flag_Array($T), enum_vals: []T) -> bool {
    for enum_vals {
        if !is_set(array, it) {
            return false;
        }
    }
    return true;
}

are_any_set :: inline (array: *Long_Flag_Array($T), enum_vals: []T) -> bool {
    any_set := false;
    for enum_vals {
        any_set |= is_set(array, it);
    }
    return any_set;
}

unset_all :: inline (arr: *Long_Flag_Array($T)) {
    memset(arr.flag_sets.data, 0x00, arr.flag_sets.count);
}

set_all :: inline (arr: *Long_Flag_Array($T)) {
    memset(arr.flag_sets.data, 0xff, arr.flag_sets.count);
}
