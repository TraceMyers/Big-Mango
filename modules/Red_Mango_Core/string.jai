
ASCII_TO_LOWER_DIFFERENCE :: #char "a" - #char "A";

Bound_String :: struct {
    str: string;
    max: s64;
}

bound_string :: (bound_to_str: string) -> Bound_String {
    bound: Bound_String = ---;
    bound.str.data = bound_to_str.data;
    bound.str.count = 0;
    bound.max = bound_to_str.count;
    return bound;
}

bound_string_add :: inline (bound: *Bound_String, c: u8) {
    assert(bound.str.count + 1 <= bound.max);
    bound.str.count += 1;
    bound.str.data[bound.str.count-1] = c;
}

bound_string_append :: inline (bound: *Bound_String, s: string) {
    assert(bound.str.count + s.count <= bound.max);
    memcpy(bound.str.data + bound.str.count, s.data, s.count);
    bound.str.count += s.count;
}

bound_string_reset :: inline (bound: *Bound_String, keep_data_reference := true) {
    if !keep_data_reference {
        bound.str.data = null;
        bound.max = 0;
    }
    bound.str.count = 0;
}

reset :: inline (s: *string) {
    if s.data != null {
        free(s.data);
        s.data = null;
    }
    s.count = 0;
}

as_array :: inline (str: string, $T: Type) -> []T {
    t_array: []T = ---;
    t_array.count = str.count / size_of(T);
    t_array.data = xx str.data;
    assert(t_array.count * size_of(T) == str.count);
    return t_array;
}

as_string :: inline (array: []$T) -> string {
    return string.{array.count * size_of(T), xx array.data};
}

as_string :: inline (item: $T) -> string 
#modify {
    info := cast(*Type_Info)T;
    if info.type == .ARRAY {
        return false;
    }
    return true;
} {
    return string.{size_of(T), xx *item};
}

to_lower :: inline (str: string, allocator := context.allocator) -> string {
    out_str := alloc_string(str.count,,allocator);
    for str {
        out_str[it_index] = to_lower(it);
    }
    return out_str;
}

to_upper :: inline (str: string, allocator := context.allocator) -> string {
    out_str := alloc_string(str.count,,allocator);
    for str {
        out_str[it_index] = to_upper(it);
    }
    return out_str;
}

concatenate :: (strings: ..string, allocator := context.allocator) -> string {
    out_count := 0;
    for strings {
        out_count += it.count;
    }
    out_str := alloc_string(out_count,,allocator);
    bound := bound_string(out_str);
    for strings {
        bound_string_append(*bound, it);
    }
    assert(bound.str.count == out_str.count);
    return out_str;
}

reverse :: (str: string) {
    b: s64;
    half_count := str.count >> 1;
    while b <= half_count {
        e := str.count - 1 - b;
        str[b], str[e] = str[e], str[b];
        b += 1;
    }
}

find_index_from_left :: inline (str: string, pattern: string, $COMPARE_LOWER := false, $asterisk_is_wildcard := false) -> s64 {
    match_count := 0;
    for 0..str.count-1 {
        c := str[it];
        is_match := false;
        #if COMPARE_LOWER {
            is_match = to_lower(c) == to_lower(pattern[match_count]);
        } else {
            is_match = c == pattern[match_count];
        }
        #if asterisk_is_wildcard {
            is_match |= pattern[match_count] == #char "*";
        }
        if is_match {
            match_count += 1;
            if match_count == pattern.count {
                return it - match_count + 1;
            }
        } else {
            remain_ct := str.count - it - 1;
            if remain_ct < pattern.count {
                break;
            }
            match_count = 0;
        }
    }
    return -1;
}

is_alpha_upper :: inline (code_point: u32) -> bool {
    return code_point <= #char "Z" && code_point >= #char "A";
}

is_alpha_lower :: inline (code_point: u32) -> bool {
    return code_point <= #char "z" && code_point >= #char "a";
}

is_slash :: inline (code_point: u32) -> bool {
    return code_point == #char "/" || code_point == #char "\\";
}

is_whitespace :: inline (code_point: u32) -> bool {
    return code_point == #char " " || code_point == #char "\t" || code_point == #char "\n";
}

to_upper :: inline (c: $T, $CHECKED := true) -> T {
    #if CHECKED {
        if !is_alpha_lower(c) {
            return c;
        }
    }
    return c - ASCII_TO_LOWER_DIFFERENCE;
}

to_lower :: inline (c: $T, $CHECKED := true) -> T {
    #if CHECKED {
        if !is_alpha_upper(c) {
            return c;
        }
    }
    return c + ASCII_TO_LOWER_DIFFERENCE;
}

copy :: (s: string, allocator := context.allocator) -> string {
    if s.count == 0 return "";
    copy := alloc_string(s.count,,allocator);
    memcpy(copy.data, s.data, s.count);
    return copy;
}

string_data_overlaps :: inline (s1: string, s2: string) -> bool {
    s1_min_address := s1.data.(u64);
    s1_max_address := (s1.data + (s1.count-1)).(u64);
    s2_min_address := s2.data.(u64);
    s2_max_address := (s2.data + (s2.count-1)).(u64);
    return ordered_ranges_overlap(s1_min_address, s1_max_address, s2_min_address, s2_max_address);
}

process_per_line :: (str: string, per_line_proc: (line: *string, line_index: s64, in_data: *void), in_data: *void) -> line_count: s64 {
    line_count: s64;
    left, right: string;
    right = str;
    success: bool;
    while true {
        prev_right := right;
        success, left, right = split_from_left(right, #char "\n");
        if !success {
            if prev_right.count > 0 {
                per_line_proc(*prev_right, line_count, in_data); 
                line_count += 1;
            }
            break;
        }
        if left.count > 0 && left[left.count-1] == #char "\r" {
            left.count -= 1;
        }
        per_line_proc(*left, line_count, in_data); 
        line_count += 1;
    }
    return line_count;
}

c_strings_equal :: (a: *u8, b: *u8, max_read_count: s64) -> bool {
    if max_read_count <= 0 {
        return false;
    }
    for i : 0..max_read_count-1 {
        if a[i] == 0 {
            if b[i] == 0 {
                return true;
            } else {
                return false;
            }
        } else if b[i] == 0 {
            return false;
        }
        if a[i] != b[i] {
            return false;
        }
    }
    return true;
}

tokenize_and_trim :: (s: string, separator: u8, allocator:=context.allocator) -> []string {
    scope_set_allocator(allocator);
    strings := split(s, separator);
    for *strings {
        it.* = trim(it.*);
    }
    for #v2 < 0..strings.count-1 {
        if strings[it].count == 0 {
            if it < strings.count - 1 {
                for i : it..strings.count-2 {
                    strings[i] = strings[i+1];
                }
            }
            strings.count -= 1;
        }
    }
    return strings;
}

// tokenize_and_trim :: (s: string, separator: string) -> []string {
//     strings := split(s, separator);
//     for *strings {
//         it.* = trim(it.*);
//     }
//     for #v2 < 0..strings.count-1 {
//         if strings[it].count == 0 {
//             if it < strings.count - 1 {
//                 for i : it..strings.count-2 {
//                     strings[i] = strings[i+1];
//                 }
//             }
//             strings.count -= 1;
//         }
//     }
//     return strings;
// }