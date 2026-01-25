// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

// note: don't need bit serialization. can just use separate bit flags for that. no reason to inline the bits I can think of.
// note: don't need a struct for combining the data with a checksum. should just have the serializer leave the first
// 128 bits open for the checksum if it's going to have one.
// todo: if alignment isn't PRIMITIVE, structs need to be packed/unpacked

SERIALIZER_CHECKSUM_SIZE :: 32;
CHECKSUM_UINT32_COUNT :: SERIALIZER_CHECKSUM_SIZE / 4;
SERIALIZER_CHECKSUM_TYPE :: [CHECKSUM_UINT32_COUNT]u32;

Rw_Mode :: enum u8 {
    WRITE;
    READ;
}

Serializer :: struct($in_alloc_mode: Serializer_Alloc_Mode = .STATIC, $in_align_mode: Serializer_Align_Mode = .BYTE) {
    memory: string;
    allocator: Allocator; // only used if dynamic
    // used only when reading out arrays. if not set, will default to using the above allocator.
    read_array_allocator: Allocator; 
    head: s32;
    parameter_align : u8 = 1; // must be power of 2 if used
    rw_mode: Rw_Mode;
    pad_for_checksum := false;
    alloc_mode :: in_alloc_mode;
    align_mode :: in_align_mode;
#overlay(memory) // for debug
    memory_count: s64; 
    memory_data: *u8;
    reverse_byte_order: bool;
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
set_rw_mode :: (using buffer: *Serializer($alloc_m, $align_m), m: Rw_Mode, use_checksum := false, do_reverse_bytes := false) {
    rw_mode = m;
    pad_for_checksum = use_checksum;
    if pad_for_checksum {
        head = SERIALIZER_CHECKSUM_SIZE;
    } else {
        head = 0;
    }
    reverse_byte_order = do_reverse_bytes;
}

reset :: (using buffer: *Serializer($alloc_m, $align_m), keep_allocation := true) {
    if !keep_allocation {
        reset(*memory);
    }
    set_rw_mode(buffer, rw_mode, pad_for_checksum, reverse_byte_order);
}

// warning: this can't reverse bytes, if that function is needed
write_entire_file :: (name: string, buffer: *Serializer($alloc_m, $align_m)) -> bool {
    str := string.{buffer.head, buffer.memory.data};
    return write_entire_file(name, str);
}

view_bytes_before_head :: (using buffer: *Serializer($alloc_m, $align_m)) -> string {
    return string.{head, memory.data};
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
    if reverse_byte_order {
        item_copy := item;
        reverse_bytes((*item).(*u8), (*item_copy).(*u8), size_of(T));
    }
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
// dynamic arrays

serialize :: (using buffer: *Serializer($alloc_m, $align_m), array: *[..]$T) 
#modify {
    return is_serial_primitive(T);
} {
    if rw_mode == .WRITE {
        serialize_dynamic_array(buffer, array, .WRITE);
    } else {
        serialize_dynamic_array(buffer, array, .READ);
    }
}

serialize :: (using buffer: *Serializer($alloc_m, $align_m), array: *[..]$T, array_count: s32) 
#modify {
    return is_serial_primitive(T);
} {
    if rw_mode == .WRITE {
        serialize_dynamic_array_data(buffer, array, array_count, .WRITE);
    } else {
        serialize_dynamic_array_data(buffer, array, array_count, .READ);
    }
}

serialize_dynamic_array :: (using buffer: *Serializer($alloc_m, $align_m), array: *[..]$T, $mode: Rw_Mode)
#modify {
    return is_serial_primitive(T);
} {
    array_count: s32 = xx array.count;
    serialize_primitive(buffer, *array_count, mode);
    serialize_dynamic_array_data(buffer, array, array_count, mode);
}

serialize_dynamic_array_data :: (using buffer: *Serializer($alloc_m, $align_m), array: *[..]$T, array_count: s32, $mode: Rw_Mode)
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
        array_data_write(memory.data + head, array.data, array_size, reverse_byte_order);
    } else {
        if array.data == null {
            array_resize(array, array_count, false);
        } else {
            assert(array.count >= array_count);
        }
        array_data_read(memory.data + head, array.data, array_size, reverse_byte_order);
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
        array_data_write(memory.data + head, array.data, array_size, reverse_byte_order);
    } else {
        if array.data == null {
            use_allocator := ifx read_array_allocator.proc != null then read_array_allocator else allocator;
            array.* = array_alloc(T, array_count,, use_allocator);
        }
        assert(array.count >= array_count);
        array_data_read(memory.data + head, array.data, array_size, reverse_byte_order);
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

serialize_bytes :: inline (using buffer: *Serializer($alloc_m, $align_m), data: *u8, count: s32, $mode: Rw_Mode) {
    array: []u8 = ---;
    array.count = xx count;
    array.data = data;
    serialize_array_data(buffer, *array, count, mode);
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

validate_checksum :: no_inline (using buffer: *Serializer($alloc_m, $align_m)) -> bool {
    assert(pad_for_checksum);
    assert(memory.count > SERIALIZER_CHECKSUM_SIZE);
    calculated: [CHECKSUM_UINT32_COUNT]u32;
    calculate_checksum(buffer, calculated.data);
    have : *[CHECKSUM_UINT32_COUNT]u32 = xx memory.data;
    for 0..CHECKSUM_UINT32_COUNT-1 {
        if have.*[it] != calculated[it] then return false;
    }
    return true;
}

imprint_checksum :: (using buffer: *Serializer($alloc_m, $align_m)) {
    assert(pad_for_checksum);
    assert(memory.count > SERIALIZER_CHECKSUM_SIZE);
    calculate_checksum(buffer, xx memory.data);
}

calculate_checksum :: (using buffer: *Serializer($alloc_m, $align_m), out: *u32) {
    assert(pad_for_checksum);
    assert(memory.count > SERIALIZER_CHECKSUM_SIZE);
    assert(head >= SERIALIZER_CHECKSUM_SIZE);
    bufstr := string.{memory.count - SERIALIZER_CHECKSUM_SIZE, memory.data + SERIALIZER_CHECKSUM_SIZE};
    {
        scope_set_allocator(temp);
        auto_release_temp();
        str := md5(bufstr);
        array := as_array(str, u32);
        assert(array.count == CHECKSUM_UINT32_COUNT);
        memcpy(out, array.data, size_of(u32) * CHECKSUM_UINT32_COUNT);
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
        assert(new_head <= memory.count, "old head: %, new head: %, memory.count: %", head, new_head, memory.count);
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

// iterate over struct members and reverse bytes of each member. NOT recursive. todo: maybe should be recursive
reverse_bytes :: (in: *$T) 
#modify {
    tinfo := T.(*Type_Info);
    return tinfo.type == .STRUCT;
} {
    byte_buffer: [size_of(T)]u8 = ---;
    memcpy(byte_buffer.data, in, size_of(T));

    for info : T.(*Type_Info_Struct).members {
        in\_field_ptr := byte_buffer.data + info.offset_in_bytes;
        out_field_ptr := in.(*u8) + info.offset_in_bytes;
        for 0..info.type.runtime_size-1 {
            out_field_ptr[it] = in_field_ptr[(info.type.runtime_size-1) - it];
        }
    }
}

reverse_bytes :: inline (in: $T) -> T
#modify {
    tinfo := T.(*Type_Info);
    if tinfo.type == {
    case .INTEGER; 
        #through;
    case .FLOAT; 
        #through;
    case .BOOL; 
        #through;
    case .ENUM;
        return true;
    }
    return false;
} {
    out: T = ---;
    TYPE_SIZE :: #run T.(*Type_Info).runtime_size;
    #if TYPE_SIZE == {
    case 1;
        return in;
    case;
        reverse_bytes((*out).(*u8), (*in).(*u8), TYPE_SIZE);
    }
    return out;
}

reverse_bytes :: (bytes_out: *u8, bytes_in: *u8, size: s32) {
    assert(size > 0);
    if size == {
    case 1;
        bytes_out.* = bytes_in.*;
    case 2;
        bytes_out[0], 
        bytes_out[1]  = 
                        bytes_in[1], 
                        bytes_in[0];
    case 4;
        bytes_out[0],
        bytes_out[1],
        bytes_out[2],
        bytes_out[3]  =
                        bytes_in[3],
                        bytes_in[2],
                        bytes_in[1],
                        bytes_in[0];
    case 8;
        bytes_out[0],
        bytes_out[1],
        bytes_out[2],
        bytes_out[3],
        bytes_out[4],
        bytes_out[5],
        bytes_out[6],
        bytes_out[7]  =
                        bytes_in[7],
                        bytes_in[6],
                        bytes_in[5],
                        bytes_in[4],
                        bytes_in[3],
                        bytes_in[2],
                        bytes_in[1],
                        bytes_in[0];
    case;
        assert(bytes_out != bytes_in, "can't do byte swaps in a for loop (not sure why), so pointers should not alias");
        for 0..size-1 {
            bytes_out[it] = bytes_in[(size-1)-it];
        }
    }
}

// ---------------------------------------------------------------------------------------------------------------------
#scope_file // ---------------------------------------------------------------------------------------------- SCOPE_FILE
// ---------------------------------------------------------------------------------------------------------------------

write_primitive :: inline (using buffer: *Serializer($alloc_m, $align_m), primitive: *$T) {
    if reverse_byte_order {
        #if #run T.(*Type_Info).type == .STRUCT {
            copy := primitive.*;
            reverse_bytes(*copy);
            memcpy(memory.data + head, *copy, size_of(T));
        } else {
            reverse_bytes(memory.data + head, primitive.(*u8), size_of(T));
        }
    } else {
        #if #complete align_mode == {
        case .PRIMITIVE;
            (memory.data + head).(*T).* = primitive.*;
        case .PARAMETER; 
            memcpy(memory.data + head, primitive, size_of(T));
        case .BYTE;
            memcpy(memory.data + head, primitive, size_of(T));
        }
    }
}

read_primitive :: inline (using buffer: *Serializer($alloc_m, $align_m), primitive: *$T) {
    if reverse_byte_order {
        #if #run T.(*Type_Info).type == .STRUCT {
            memcpy(primitive, memory.data + head, size_of(T));
            reverse_bytes(primitive); 
        } else {
            reverse_bytes(primitive.(*u8), memory.data + head, size_of(T));
        }
    } else {
        #if #complete align_mode == {
        case .PRIMITIVE;
             primitive.* = (memory.data + head).(*T).*;
        case .PARAMETER;
            memcpy(primitive, memory.data + head, size_of(T));
        case .BYTE;
            memcpy(primitive, memory.data + head, size_of(T));
        }
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
    assert(`rw_mode == `mode, "expected mode %, have mode %", `mode, `rw_mode);
    if `pad_for_checksum {
        assert(`head >= SERIALIZER_CHECKSUM_SIZE);
    }
}

array_data_write :: inline (serializer_data: *u8, array_data: *$T, array_size: s64, reverse_byte_order: bool) {
    memcpy(serializer_data, array_data, array_size);
}

array_data_read :: (serializer_data: *u8, array_data: *$T, array_size: s64, reverse_byte_order: bool) #expand {
    memcpy(array_data, serializer_data, array_size);
}


#import "md5";
