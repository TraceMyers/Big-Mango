
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

lfa_is_set :: inline (arr: *Long_Flag_Array($T), enum_val: T) -> bool {
    indexer := convert_to_lfa_indexer(xx enum_val);
    return (arr.flag_sets[indexer.index] & ((1).(u8) << indexer.bit)) != 0;
}

lfa_set :: inline (arr: *Long_Flag_Array($T), enum_val: T) {
    indexer := convert_to_lfa_indexer(xx enum_val);
    arr.flag_sets[indexer.index] |= ((1).(u8) << indexer.bit);
}

lfa_unset :: inline (arr: *Long_Flag_Array($T), enum_val: T) {
    indexer := convert_to_lfa_indexer(xx enum_val);
    arr.flag_sets[indexer.index] &= ~((1).(u8) << indexer.bit);
}

lfa_set_multiple :: inline (arr: *Long_Flag_Array($T), enum_vals: []T) {
    for enum_vals {
        lfa_set(arr, it);
    }
}

lfa_unset_multiple :: inline (arr: *Long_Flag_Array($T), enum_vals: []T) {
    for enum_vals {
        lfa_unset(arr, it);
    }
}

lfa_unset_all :: inline (arr: *Long_Flag_Array($T)) {
    memset(arr.flag_sets.data, 0x00, size_of(u8) * arr.flag_sets.count);
}

lfa_set_all :: inline (arr: *Long_Flag_Array($T)) {
    memset(arr.flag_sets.data, 0xff, size_of(u8) * arr.flag_sets.count);
}
