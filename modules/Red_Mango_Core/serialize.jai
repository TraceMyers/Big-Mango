// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// for writing forward into a buffer and reading backward.

// note: don't need bit serialization. can just use separate bit flags for that. no reason to inline the bits I can think of.
// note: don't need a struct for combining the data with a checksum. should just have the serializer leave the first
// 128 bits open for the checksum if it's going to have one.
// todo: if alignment isn't PRIMITIVE, structs need to be packed/unpacked

SERIALIZER_CHECKSUM_TYPE :: [4]u32;
SERIALIZER_CHECKSUM_SIZE :: size_of(SERIALIZER_CHECKSUM_TYPE);

Rw_Mode :: enum u8 {
    WRITE;
    READ;
}

Serializer :: struct($in_alloc_mode: Serializer_Alloc_Mode = .STATIC, $in_align_mode: Serializer_Align_Mode = .BYTE) {
    memory: string;
    // TODO: parallel array of tags. push on write, pop on read. check against T.
    // #if SERIALIZE_DEBUG {
        // dbg_tags: [..]Type_Info_Tag;
    //     dbg_i: s64;
    // }
    allocator: Allocator; // only used if dynamic
    // used only when reading out arrays. if not set, will default to using the above allocator.
    read_array_allocator: Allocator; 
    head: s32;
    parameter_align : u8 = 1; // must be power of 2 if used
    rw_mode: Rw_Mode;
    pad_for_checksum := false;
    alloc_mode :: in_alloc_mode;
    align_mode :: in_align_mode;
}

Serializer_Alloc_Mode :: enum u8 {
    STATIC;
    DYNAMIC;
}

Serializer_Align_Mode :: enum u8 {
    BYTE;
    PRIMITIVE;
    PARAMETER;
}

// should be called after pad_for_checksum is set, if it is being set
set_rw_mode :: (using buffer: *Serializer($alloc_m, $align_m), m: Rw_Mode, use_checksum := true) {
    rw_mode = m;
    pad_for_checksum = use_checksum;
    if pad_for_checksum {
        head = SERIALIZER_CHECKSUM_SIZE;
    } else {
        head = 0;
    }
}

reset :: (using buffer: *Serializer($alloc_m, $align_m), keep_allocation := true) {
    if !keep_allocation {
        reset(*memory);
    }
    set_rw_mode(buffer, .WRITE);
}

write_entire_file :: (name: string, buffer: *Serializer($alloc_m, $align_m)) -> bool {
    str := string.{buffer.head, buffer.memory.data};
    return write_entire_file(name, str);
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// convenience procs

write               :: #bake_arguments serialize_primitive(mode=.WRITE);
read                :: #bake_arguments serialize_primitive(mode=.READ);
write_array         :: #bake_arguments serialize_array(mode=.WRITE);
read_array          :: #bake_arguments serialize_array(mode=.READ);
write_array_data    :: #bake_arguments serialize_array_data(mode=.WRITE);
read_array_data     :: #bake_arguments serialize_array_data(mode=.READ);
write_string        :: #bake_arguments serialize_string(mode=.WRITE);
read_string         :: #bake_arguments serialize_string(mode=.READ);
write_bytes         :: #bake_arguments serialize_bytes(mode=.WRITE);
read_bytes          :: #bake_arguments serialize_bytes(mode=.READ);

read_out :: inline (using buffer: *Serializer($alloc_m, $align_m), $T: Type) -> T 
#modify {
    return is_serial_primitive(T);
} {
    item: T = ---;
    read(buffer, *item);
    return item;
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// primitives

serialize :: (using buffer: *Serializer($alloc_m, $align_m), item: *$T) 
#modify {
    return is_serial_primitive(T);
} {
    if rw_mode == .WRITE {
        serialize_primitive(buffer, item, .WRITE);
    } else {
        serialize_primitive(buffer, item, .READ);
    }
}

serialize_primitive :: (using buffer: *Serializer($alloc_m, $align_m), item: *$T, $mode: Rw_Mode) 
#modify {
    return is_serial_primitive(T);
} {
    validate_read_write();
    align_head_up_for_type(buffer, T);
    new_head := head + size_of(T);
    check_new_head(buffer, new_head);
    
    #if mode == .WRITE {
        write_primitive(buffer, item);
    } else {
        read_primitive(buffer, item);
    }

    head = new_head;
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// arrays

serialize :: (using buffer: *Serializer($alloc_m, $align_m), array: *[]$T) 
#modify {
    return is_serial_primitive(T);
} {
    if rw_mode == .WRITE {
        serialize_array(buffer, array, .WRITE);
    } else {
        serialize_array(buffer, array, .READ);
    }
}

serialize :: (using buffer: *Serializer($alloc_m, $align_m), array: *[]$T, array_count: s32) 
#modify {
    return is_serial_primitive(T);
} {
    if rw_mode == .WRITE {
        serialize_array_data(buffer, array, array_count, .WRITE);
    } else {
        serialize_array_data(buffer, array, array_count, .READ);
    }
}

serialize_array :: (using buffer: *Serializer($alloc_m, $align_m), array: *[]$T, $mode: Rw_Mode)
#modify {
    return is_serial_primitive(T);
} {
    array_count: s32 = xx array.count;
    serialize_primitive(buffer, *array_count, mode);
    serialize_array_data(buffer, array, array_count, mode);
}

serialize_array_data :: (using buffer: *Serializer($alloc_m, $align_m), array: *[]$T, array_count: s32, $mode: Rw_Mode)
#modify {
    return is_serial_primitive(T);
} {
    validate_read_write();
    if array_count == 0 {
        return;
    }
    align_head_up_for_type(buffer, T);
    array_size := size_of(T) * array_count;
    new_head := head + array_size;
    check_new_head(buffer, new_head);
    #if mode == .WRITE {
        memcpy(memory.data + head, array.data, array_size);
    } else {
        if array.data == null {
            use_allocator := ifx read_array_allocator.proc != null then read_array_allocator else allocator;
            array.* = alloc_array(T, array_count, use_allocator);
        } else {
            assert(array.count >= array_count);
        }
        memcpy(array.data, memory.data + head, array_size);
    }
    head = new_head;
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// nested arrays

serialize :: (using buffer: *Serializer($alloc_m, $align_m), array: *Nested_Array($T, $S), nesting_allocator: *Nesting_Allocator(S)) 
#modify {
    return is_serial_primitive(T) || T == string;
} {
    if rw_mode == .WRITE {
        serialize_nested_array(buffer, array, nesting_allocator, .WRITE);
    } else {
        serialize_nested_array(buffer, array, nesting_allocator, .READ);
    }
}

serialize_nested_array :: (using buffer: *Serializer($alloc_m, $align_m), array: *Nested_Array($T, $S), nesting_allocator: *Nesting_Allocator(S), $mode: Rw_Mode) 
#modify {
    return is_serial_primitive(T) || T == string;
} {
    array_count: s32 = xx array.field.count;
    serialize_primitive(buffer, *array_count, mode);
    serialize_nested_array_data(buffer, array, nesting_allocator, array_count, mode);
}

serialize_nested_array_data :: (using buffer: *Serializer($alloc_m, $align_m), array: *Nested_Array($T, $S), nesting_allocator: *Nesting_Allocator(S), array_count: s32, $mode: Rw_Mode) 
#modify {
    return is_serial_primitive(T) || T == string;
} {
    validate_read_write();
    if array_count == 0 {
        return;
    }
    
    new_head := head;
    array_size: s32;

    #if T == string {
        align_head_up_for_type(buffer, u8);
        array_size = array_count;
    } else {
        align_head_up_for_type(buffer, T);
        array_size = xx (size_of(T) * array_count);
    }

    new_head += array_size;
    check_new_head(buffer, new_head);
    #if mode == .WRITE {
        if array_count > 0 {
            memcpy(memory.data + head, array.field.data, array_size);
        }
    } else {
        assert(array.field.data == null);
        array_resize(array, nesting_allocator, array_count);
        if array_count > 0 {
            memcpy(array.field.data, memory.data + head, array_size);
        }
    }

    head = new_head;
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// strings

serialize :: (using buffer: *Serializer($alloc_m, $align_m), str: *string) {
    if rw_mode == .WRITE {
        serialize_string(buffer, str, .WRITE);
    } else {
        serialize_string(buffer, str, .READ);
    }
}

serialize_string :: (using buffer: *Serializer($alloc_m, $align_m), str: *string, $mode: Rw_Mode) {
    assert(rw_mode == mode);
    array: []u8;
    #if mode == .WRITE {
        array.data = str.data;
        array.count = str.count;
        serialize_array(buffer, *array, .WRITE);
    } else {
        serialize_array(buffer, *array, .READ);
        str.data = array.data;
        str.count = array.count;
    }
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// bytes

serialize :: (using buffer: *Serializer($alloc_m, $align_m), data: *u8, count: s64) {
    if rw_mode == .WRITE {
        serialize_bytes(buffer, data, xx count, .WRITE);
    } else {
        serialize_bytes(buffer, data, xx count, .READ);
    }
}

serialize_bytes :: (using buffer: *Serializer($alloc_m, $align_m), data: *u8, count: s32, $mode: Rw_Mode) {
    array: []u8 = ---;
    array.count = xx count;
    array.data = data;
    serialize_array_data(buffer, *array, count, mode);
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

validate_checksum ::(using buffer: *Serializer($alloc_m, $align_m)) -> bool {
    assert(pad_for_checksum);
    assert(memory.count > SERIALIZER_CHECKSUM_SIZE);
    calculated: [4]u32;
    calculate_checksum(buffer, *calculated);
    have : *[4]u32 = xx memory.data;
    for 0..3 {
        if have.*[it] != calculated[it] then return false;
    }
    return true;
}

imprint_checksum :: (using buffer: *Serializer($alloc_m, $align_m)) {
    assert(pad_for_checksum);
    assert(memory.count > SERIALIZER_CHECKSUM_SIZE);
    calculate_checksum(buffer, xx memory.data);
}

calculate_checksum :: (using buffer: *Serializer($alloc_m, $align_m), out: *[4]u32) {
    assert(pad_for_checksum);
    assert(memory.count > SERIALIZER_CHECKSUM_SIZE);
    assert(head >= SERIALIZER_CHECKSUM_SIZE);
    bufstr := string.{head - SERIALIZER_CHECKSUM_SIZE, memory.data + SERIALIZER_CHECKSUM_SIZE};
    {
        scope_set_allocator(temp);
        auto_release_temp();
        str := md5(bufstr);
        array := as_array(str, u32);
        memcpy(out.data, array.data, size_of(u32) * 4);
    }
}

align_head_up :: (using buffer: *Serializer($alloc_m, $align_m), align: u8) {
    new_head := ceil_to_pow2_multiple(head, align);
    diff := new_head - head;
    if diff > 0 {
        advance_head(buffer, diff);
    } else assert(diff == 0);
}

check_new_head :: (using buffer: *Serializer($alloc_m, $align_m), new_head: s32) {
    assert(new_head >= 0);
    #if alloc_mode == .STATIC {
        assert(new_head <= memory.count);
    } else { // DYNAMIC
        desired_capacity := max(ceil_to_pow2_multiple(new_head, 2), 256);
        if memory.count < desired_capacity {
            scope_set_allocator(allocator);
            new_memory := alloc_string(desired_capacity);
            memcpy(new_memory.data, memory.data, memory.count);
            free(memory.data);
            memory = new_memory;
        }
    }
}

advance_head :: inline (using buffer: *Serializer($alloc_m, $align_m), by_count: s32) {
    new_head := head + by_count;
    assert(by_count > 0);
    assert(head >= 0 && head <= memory.count);
    assert(new_head >= 0 && new_head <= memory.count);
    head = new_head;
}

align_head_up_for_type :: (using buffer: *Serializer($alloc_m, $align_m), $T: Type) {
    align_head_up(buffer, serial_primitive_alignment(buffer, T));
}

align_head_up_for_array :: (using buffer: *Serializer($alloc_m, $align_m), $T: Type) {
    #if #complete align_mode == {
    case .PRIMITIVE;
        align_head_up(buffer, 4);
    case .PARAMETER;
        align_head_up(buffer, parameter_align);
    case .BYTE;
    }
}

// ---------------------------------------------------------------------------------------------------------------------
#scope_file // ---------------------------------------------------------------------------------------------- SCOPE_FILE
// ---------------------------------------------------------------------------------------------------------------------

write_primitive :: inline (using buffer: *Serializer($alloc_m, $align_m), primitive: *$T) {
    #if #complete align_mode == {
    case .PRIMITIVE;
        (memory.data + head).(*T).* = primitive.*;
    case .PARAMETER;
        memcpy(memory.data + head, primitive, size_of(T));
    case .BYTE;
        memcpy(memory.data + head, primitive, size_of(T));
    }
}

read_primitive :: inline (using buffer: *Serializer($alloc_m, $align_m), primitive: *$T) {
    #if #complete align_mode == {
    case .PRIMITIVE;
         primitive.* = (memory.data + head).(*T).*;
    case .PARAMETER;
        memcpy(primitive, memory.data + head, size_of(T));
    case .BYTE;
        memcpy(primitive, memory.data + head, size_of(T));
    }
}

serial_primitive_alignment :: inline (using buffer: *Serializer($alloc_m, $align_m), $T: Type) -> u8 {
    T_ALIGNMENT : u8 : #run align_of(T);
    #if #complete align_mode == {
    case .PRIMITIVE;
        return T_ALIGNMENT;
    case .PARAMETER;
        return parameter_align;
    case .BYTE;
        return 1;
    }
    return 1;
}

is_serial_primitive :: (T: Type) -> bool {
    info := cast(*Type_Info)T;
    if info.type == .INTEGER return true;
    if info.type == .FLOAT   return true;
    if info.type == .BOOL    return true;
    if info.type == .ENUM    return true;
    if info.type == .STRUCT  return true;
    return false;
}

validate_read_write :: () #expand {
    assert(`rw_mode == `mode);
    if `pad_for_checksum {
        assert(`head >= SERIALIZER_CHECKSUM_SIZE);
    }
}

// ---------------------------------------------------------------------------------------------------------------------
#scope_file // ---------------------------------------------------------------------------------------------- SCOPE_FILE
// ---------------------------------------------------------------------------------------------------------------------

#import "md5";