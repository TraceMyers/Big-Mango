KILOBYTE :: 1024;
MEGABYTE :: 1024 * 1024;
GIGABYTE :: 1024 * 1024 * 1024;

is_number_type :: (In_Type: Type) -> bool {
    return (cast(*Type_Info)In_Type).type == .INTEGER || (cast(*Type_Info)In_Type).type == .FLOAT;
}

is_int_type :: (In_Type: Type) -> bool {
    return (cast(*Type_Info)In_Type).type == .INTEGER;
}

is_float_type :: (In_Type: Type) -> bool {
    return (cast(*Type_Info)In_Type).type == .FLOAT;
}

min_value :: inline (number: $Number_Type) -> Number_Type #expand {
    return min_value(type_of(number));
}

max_value :: inline (number: $Number_Type) -> Number_Type #expand {
    return max_value(type_of(number));
}

// ceil to a multiple of a power of 2
// todo: rename to something better
ceil_to_pow2_multiple :: inline (n: $T, power_of_two_size: T) -> T {
    assert(is_power_of_two(power_of_two_size));
    return (n + power_of_two_size-1) & ~(power_of_two_size-1);
}

// floor to a multiple of a power of 2
// todo: rename to something better
floor_to_pow2_multiple :: inline (n: $T, power_of_two_size: T) -> T {
    assert(is_power_of_two(power_of_two_size));
    return n & ~(power_of_two_size-1);
}

ceil_to_pow2 :: inline (n: $T) -> T {
    if n == 0 {
        return 0;
    } else if !is_power_of_two(n) {
        return xx ((1).(u64) << (bit_scan_reverse(n)).(u64));
    } else return n;
}

is_multiple_of_type_size :: (number: $AnyInt, $RelevantType: Type) -> bool {
    SHIFT :: #run shift_for_divide(Relevant_type);
    return number != 0 && ((number >> SHIFT) << SHIFT) == number;
}

shift_for_divide :: inline ($Number_Type: Type) -> u8 {
    #if size_of(Number_Type) == {
    case 1;
        return 0;
    case 2;
        return 1;
    case 4;
        return 2;
    case 8;
        return 3;
    case;
        assert(false, "invalid number size");
    }
    return 0;
}

min_value :: ($Number_Type: Type) -> Number_Type
#modify {
    return is_number_type(Number_Type);
} {
    #if Number_Type == {
    case u8;
        return 0;
    case u16; 
        return 0;
    case u32; 
        return 0;
    case u64;
        return 0;
    case s8;
        return S8_MIN;
    case s16;
        return S16_MIN;
    case s32;
        return S32_MIN;
    case s64;
        return S64_MIN;
    case float32;
        return FLOAT32_MIN;
    case float64;
        return FLOAT64_MIN;
    case;
        return 0;
    }
}

max_value :: ($Number_Type: Type) -> Number_Type
#modify {
    return is_number_type(Number_Type);
} {
    #if Number_Type == {
    case u8;
        return U8_MAX;
    case u16;
        return U16_MAX;
    case u32;
        return U32_MAX;
    case u64;
        return U64_MAX;
    case s8;
        return S8_MAX;
    case s16;
        return S16_MAX;
    case s32;
        return S32_MAX;
    case s64;
        return S64_MAX;
    case float32;
        return FLOAT32_MAX;
    case float64;
        return FLOAT64_MAX;
    case;
        return 0;
    }
}