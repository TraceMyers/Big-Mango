encode_text :: (in: string, from: Text_Encoding, to: Text_Encoding, null_terminate := false, allocator := context.allocator, assert_success := false) -> string, bool {
    text_bytes := temp_dynamic_array(u8, in.count);
    string_index: s64;
    success := true;

    // encode into a byte array
    while string_index < in.count {
        max_bytes := min(in.count-string_index, 4);
        c := encode_text(*in.data[string_index], from, to, max_bytes);
        if !c.encode_success {
            if assert_success {
                assert(false, "failed to encode from % to %", from, to);
            }
            array_reset(*text_bytes);
            success = false;
            break;
        }
        rm_encode_append(*text_bytes, c); 
        string_index += c.read_count;
    }

    subtract_null_byte_ct := 0;
    if null_terminate {
        if to == {
        case .UTF8; #through;
        case .ANSI;
            subtract_null_byte_ct = 1;
            rm_encode_repeat(*text_bytes, 0, 1);
        case .UTF16;
            subtract_null_byte_ct = 2;
            rm_encode_repeat(*text_bytes, 0, 2);
        case .UTF32;
            subtract_null_byte_ct = 4;
            rm_encode_repeat(*text_bytes, 0, 4);
        }
    }
    
    str: string = ---;
    if allocator.data == temp.data {
        str = as_string(text_bytes);
    } else {
        scope_set_allocator(allocator);
        str = copy_string(as_string(text_bytes));
    }
    str.count -= subtract_null_byte_ct;

    return str, success;
}
encode_text_string :: #procedure_of_call encode_text("",.UTF8,.UTF32);
encode_text_checked :: #bake_arguments encode_text_string(assert_success=true);
encode_temp_text :: #bake_arguments encode_text_string(allocator=temp);
encode_temp_text_checked :: #bake_arguments encode_text_string(allocator=temp, assert_success=true);

encode_temp_c_string :: inline (in: string, from: Text_Encoding, to: Text_Encoding) -> *u8 {
    return encode_text(in, from, to, true).data;
}

encode_text :: inline (in: Code_Point, to: Text_Encoding) -> Code_Point {
    return encode_text((*in.double_word).(*u8,force), in.encoding, to);
}

as_string :: (c: Code_Point) -> string {
    return .{count=c.count, data=c.bytes.data};
}

encode_text :: (in: *u8, from: Text_Encoding, to: Text_Encoding, max_read_count := 4) -> Code_Point {
    if #complete from == {
    case .ANSI;
        if #complete to == {
        case .UTF8;
            return ansi_to_utf8(in, max_read_count);
        case .UTF16;
            return ansi_to_utf16(in, max_read_count);
        case .UTF32;
            return ansi_to_utf32(in, max_read_count);
        case .ANSI;
            return as_ansi(in, max_read_count);
        }
    case .UTF8;
        if #complete to == {
        case .UTF8;
            return as_utf8(in, max_read_count);
        case .UTF16;
            return utf8_to_utf16(in, max_read_count);
        case .UTF32;
            return utf8_to_utf32(in, max_read_count);
        case .ANSI;
            return utf8_to_ansi(in, max_read_count);
        }
    case .UTF16;
        if #complete to == {
        case .UTF8;
            return utf16_to_utf8(in, max_read_count);
        case .UTF16;
            return as_utf16(in, max_read_count);
        case .UTF32;
            return utf16_to_utf32(in, max_read_count);
        case .ANSI;
            return utf16_to_ansi(in, max_read_count);
        }
    case .UTF32;
        if #complete to == {
        case .UTF8;
            return utf32_to_utf8(in, max_read_count);
        case .UTF16;
            return utf32_to_utf16(in, max_read_count);
        case .UTF32;
            return as_utf32(in, max_read_count);
        case .ANSI;
            return utf32_to_ansi(in, max_read_count);
        }
    }
    return .{};
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// helpers

rm_encode_append :: inline (bytes: *[..]u8, code_point: Code_Point) {
    new_count := bytes.count + code_point.count;
    if new_count > bytes.allocated {
        array_reserve(bytes, max(bytes.allocated * 2, new_count));
    }
    memcpy(bytes.data + bytes.count, code_point.bytes.data, code_point.count);
    bytes.count = new_count;
}

rm_encode_repeat :: inline (bytes: *[..]u8, code_point: u8, repeat_ct: s32) {
    if repeat_ct < 1 then return;
    new_count := bytes.count + repeat_ct;
    if new_count > bytes.allocated {
        array_reserve(bytes, max(bytes.count * 2, new_count));
    }
    for 0..repeat_ct-1 {
        bytes.count += 1;
        bytes.*[bytes.count-1] = code_point;
    }
}

// returns the byte index of the code point, given a code point index
find_byte_index :: (str: string, code_point_index: s64, $ENCODING: Text_Encoding) -> s64 {
    if code_point_index <= 0 {
        return 0;
    }
    byte_read_count := 0;
    code_read_count := 0;
    while byte_read_count < str.count {
        if code_read_count == i {
            break;
        }
        code_point := to_utf32(*str[byte_read_count], str.count - byte_read_count, ENCODING);
        byte_read_count += code_point.read_count;
        code_read_count += 1;
    }
    return byte_read_count;   
}

code_point_count :: (str: string, $ENCODING: Text_Encoding) -> s64 {
    code_read_count := 0;
    byte_read_count := 0;
    while byte_read_count < str.count {
        code_point := to_utf32(*str[byte_read_count], str.count - byte_read_count, ENCODING);
        byte_read_count += code_point.read_count;
        code_read_count += 1;
    }
    return code_read_count;
}

to_utf32 :: (b: *u8, max_read_count: s64, $FROM_ENCODING: Text_Encoding) -> Code_Point {
    #if #complete FROM_ENCODING == {
    case .UTF8;
        return utf8_to_utf32(in, max_read_count);
    case .UTF16;
        return utf16_to_utf32(in, max_read_count);
    case .UTF32;
        return as_utf32(in, max_read_count);
    case .ANSI;       
        return ansi_to_utf32(in, max_read_count);
    }
}

is_ansi :: inline (in: u32) -> bool {
    return (in & 0xff) == in;
}

is_ascii :: inline (in: u32) -> bool {
    return (in & 0x7f) == in;
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// conversions

utf8_to_utf16 :: inline (b: *u8, max_read_count := 4) -> Code_Point {
    utf32 := utf8_to_utf32(b, max_read_count);
    cs := utf32_to_utf16(xx *utf32.double_word, 4);
    cs.read_count = utf32.read_count;
    return cs;
}

utf16_to_utf8 :: inline (b: *u8, max_read_count := 4) -> Code_Point {
    utf32 := utf16_to_utf32(b, max_read_count);
    cs :=  utf32_to_utf8(xx *utf32.double_word, 4);
    cs.read_count = utf32.read_count;
    return cs;
}

ansi_to_utf8 :: inline (b: *u8, max_read_count := 4) -> Code_Point {
    cs: Code_Point;
    if is_ascii(b.*) {
        cs.double_word = b.*;
        cs.count = 1;
    } else {
        cs.bytes[0] = (0xc0).(u8) | ((b.* & 0xc0) >> 6);
        cs.bytes[1] = (0x80).(u8) |  (b.* & 0x3f);
        cs.count = 2;
    }
    cs.read_count = 1;
    cs.encoding = .UTF8;
    cs.encode_success = true;
    return cs;
}

utf8_to_ansi :: inline (b: *u8, max_read_count := 4) -> Code_Point {
    utf8_cs := as_utf8(b);
    cs: Code_Point = ---;
    maybe_return_encode_failure(utf8_cs.count > 2);
    if utf8_cs.count == 1 {
        cs.double_word = b.*;
        cs.read_count = 1;
    } else {
        maybe_return_encode_failure(max_read_count < 2);
        maybe_return_encode_failure((b[0] & 0xe0) != 0xc0);
        maybe_return_encode_failure((b[1] & 0xc0) != 0x80);
        cs.double_word = ((utf8_cs.bytes[0] & 0x03) << 6).(u8) | (utf8_cs.bytes[1] & 0x3f).(u8);
        cs.read_count = 2;
    }
    cs.count = 1;
    cs.encoding = .ANSI;
    cs.encode_success = true;
    return cs;
}

utf32_to_utf8 :: inline (b: *u8, max_read_count := 4) -> Code_Point {
    cs: Code_Point = ---;
    maybe_return_encode_failure(max_read_count < 4);
    c := b.(*u32,force).*;
    maybe_return_encode_failure((c & 0xff_e0_00_00) != 0);
    if (c & 0x7f) == c {
        cs.double_word = c;
        cs.count = 1;
    } else if (c & 0x07_ff) == c {
        cs.bytes[0] = (0xc0).(u8) | ((c & 0x07_c0) >> 6).(u8);
        cs.bytes[1] = (0x80).(u8) | ( c & 0x00_3f).(u8);
        cs.count = 2;
    } else if (c & 0xff_ff) == c {
        cs.bytes[0] = (0xe0).(u8) | ((c & 0xf0_00) >> 12).(u8);
        cs.bytes[1] = (0x80).(u8) | ((c & 0x0f_c0) >> 6).(u8);
        cs.bytes[2] = (0x80).(u8) | ( c & 0x00_3f).(u8);
        cs.count = 3;
    } else {
        cs.bytes[0] = (0xf0).(u8) | ((c & 0x1c_00_00) >> 18).(u8);
        cs.bytes[1] = (0x80).(u8) | ((c & 0x03_f0_00) >> 12).(u8);
        cs.bytes[2] = (0x80).(u8) | ((c & 0x00_0f_c0) >> 6).(u8);
        cs.bytes[3] = (0x80).(u8) | ( c & 0x00_00_3f).(u8);
        cs.count = 4;
    }
    cs.read_count = 4;
    cs.encoding = .UTF8;
    cs.encode_success = true;
    return cs;
}

utf8_to_utf32 :: inline (b: *u8, max_read_count := 4) -> Code_Point {
    cs: Code_Point;
    if (b[0] & 0x80) == 0 {
        cs.double_word = b[0];
        cs.read_count = 1;
    } else if (b[0] & 0xf8) == 0xf0 {
        maybe_return_encode_failure(max_read_count < 4);
        maybe_return_encode_failure(((b[1] & 0xc0) != 0x80) | ((b[2] & 0xc0) != 0x80) | ((b[3] & 0xc0) != 0x80));
        cs.double_word = ((b[0] & 0x07) << 18).(u32) | ((b[1] & 0x3f).(u32) << 12) | ((b[2] & 0x3f).(u32) << 6) | (b[3] & 0x3f).(u32);
        cs.read_count = 4;
    } else if (b[0] & 0xf0) == 0xe0 {
        maybe_return_encode_failure(max_read_count < 3);
        maybe_return_encode_failure(((b[1] & 0xc0) != 0x80) | ((b[2] & 0xc0) != 0x80));
        cs.double_word = ((b[0] & 0x0f).(u32) << 12) | ((b[1] & 0x3f).(u32) << 6) | (b[2] & 0x3f).(u32);
        cs.read_count = 3;
    } else {
        maybe_return_encode_failure(max_read_count < 2);
        maybe_return_encode_failure((b[0] & 0xe0) != 0xc0);
        maybe_return_encode_failure((b[1] & 0xc0) != 0x80);
        cs.double_word = ((b[0] & 0x1f).(u32) << 6) | (b[1] & 0x3f).(u32);
        cs.read_count = 2;
    }
    cs.count = 4;
    cs.encoding = .UTF32;
    cs.encode_success = true;
    return cs;
}

utf32_to_utf16 :: inline (b: *u8, max_read_count := 4) -> Code_Point {
    c := b.(*u32,force).*;
    cs: Code_Point = ---;
    maybe_return_encode_failure(max_read_count < 4);
    if c > U16_MAX {
        c_20_bit := c - 0x1_00_00;
        cs.words[0] = (((c_20_bit & UTF16_HIGH_MASK) >> 10) + UTF16_HIGH_SURROGATE_MIN).(u16); // high surrogate
        cs.words[1] = ((c_20_bit & UTF16_LOW_MASK) + UTF16_LOW_SURROGATE_MIN).(u16); // low surrogate
        cs.count = 4;
    } else {
        // whole surrogate range
        maybe_return_encode_failure(c > UTF16_HIGH_SURROGATE_MIN && c < UTF16_LOW_SURROGATE_MAX);
        cs.double_word = c;
        cs.count = 2;
    }
    cs.read_count = 4;
    cs.encoding = .UTF16;
    cs.encode_success = true;
    return cs;
}

utf16_to_utf32 :: inline (b: *u8, max_read_count := 4) -> Code_Point {
    cs: Code_Point = ---;
    high_surrogate := b.(*u16,force).*;
    if high_surrogate < UTF16_HIGH_SURROGATE_MIN || high_surrogate > UTF16_HIGH_SURROGATE_MAX {
        maybe_return_encode_failure(max_read_count < 2);
        cs.double_word = high_surrogate;
        cs.read_count = 2;
    } else {
        maybe_return_encode_failure(max_read_count < 4);
        low_surrogate := (b+2).(*u16,force).*;
        maybe_return_encode_failure(low_surrogate < UTF16_LOW_SURROGATE_MIN || low_surrogate > UTF16_LOW_SURROGATE_MAX);
        _20_bit_high := (high_surrogate.(u32) - UTF16_HIGH_SURROGATE_MIN) << 10;
        _20_bit_low := low_surrogate.(u32) - UTF16_LOW_SURROGATE_MIN;
        cs.double_word = (_20_bit_high | _20_bit_low) + 0x1_00_00;
        cs.read_count = 4;
    }
    cs.count = 4;
    cs.encoding = .UTF32;
    cs.encode_success = true;
    return cs;
}

as_ansi :: inline (b: *u8, max_read_count := 4) -> Code_Point {
    assert(max_read_count >= 1);
    cs: Code_Point = ---;
    cs.double_word = b.*;
    cs.count = 1;
    cs.read_count = 1;
    cs.encoding = .ANSI;
    cs.encode_success = true;
    return cs;
}

as_utf8 :: inline (b: *u8, max_read_count := 4) -> Code_Point {
    cs: Code_Point;
    if (b[0] & 0x80) == 0 {
        maybe_return_encode_failure(!is_ascii(b.*));
        cs.bytes[0] = b[0];
        cs.count = 1;
        cs.read_count = 1;
    } else if (b[0] & 0xf8) == 0xf0 {
        maybe_return_encode_failure(max_read_count < 4);
        maybe_return_encode_failure(((b[1] & 0xc0) != 0x80) | ((b[2] & 0xc0) != 0x80) | ((b[3] & 0xc0) != 0x80));
        cs.bytes[0] = b[0];
        cs.bytes[1] = b[1];
        cs.bytes[2] = b[2];
        cs.bytes[3] = b[3];
        cs.count = 4;
        cs.read_count = 4;
    } else if (b[0] & 0xf0) == 0xe0 {
        maybe_return_encode_failure(max_read_count < 3);
        maybe_return_encode_failure(((b[1] & 0xc0) != 0x80) | ((b[2] & 0xc0) != 0x80));
        cs.bytes[0] = b[0];
        cs.bytes[1] = b[1];
        cs.bytes[2] = b[2];
        cs.count = 3;
        cs.read_count = 3;
    } else {
        maybe_return_encode_failure(max_read_count < 2);
        maybe_return_encode_failure((b[0] & 0xe0) != 0xc0);
        maybe_return_encode_failure((b[1] & 0xc0) != 0x80);
        cs.bytes[0] = b[0];
        cs.bytes[1] = b[1];
        cs.count = 2;
        cs.read_count = 2;
    }
    cs.encoding = .UTF8;
    cs.encode_success = true;
    return cs;
}

ansi_to_utf16 :: inline (b: *u8, max_read_count := 4) -> Code_Point {
    cs: Code_Point = ---;
    cs.words[0] = b[0];
    cs.words[1] = 0;
    cs.count = 2;
    cs.read_count = 1;
    cs.encoding = .UTF16;
    cs.encode_success = true;
    return cs;
}

as_utf16 :: inline (b: *u8, max_read_count := 4) -> Code_Point {
    cs: Code_Point = ---;
    cs.words[0] = b.(*u16,force).*;
    if cs.words[0] >= UTF16_HIGH_SURROGATE_MIN && cs.words[0] <= UTF16_HIGH_SURROGATE_MAX {
        maybe_return_encode_failure(max_read_count < 4);
        cs.words[1] = (*b[2]).(*u16,force).*;
        cs.count = 4;
        cs.read_count = 4;
    } else {
        maybe_return_encode_failure(max_read_count < 2);
        cs.words[1] = 0;
        cs.count = 2;
        cs.read_count = 2;
    }
    cs.encoding = .UTF16;
    cs.encode_success = true;
    return cs;
}

ansi_to_utf32 :: inline (b: *u8, max_read_count := 4) -> Code_Point {
    cs: Code_Point = ---;
    cs.double_word = b[0];
    cs.count = 4;
    cs.read_count = 1;
    cs.encoding = .UTF32;
    cs.encode_success = true;
    return cs;
}

as_utf32 :: inline (b: *u8, max_read_count := 4) -> Code_Point {
    cs: Code_Point = ---;
    maybe_return_encode_failure(max_read_count < 4);
    cs.double_word = b.(*u32,force).*;
    cs.count = 4;
    cs.read_count = 4;
    cs.encoding = .UTF32;
    cs.encode_success = true;
    return cs;
}

utf16_to_ansi :: inline (b: *u8, max_read_count := 4) -> Code_Point {
    cs: Code_Point = ---;
    maybe_return_encode_failure(max_read_count < 2);
    utf16 := b.(*u16,force).*;
    maybe_return_encode_failure(!is_ansi(utf16.(u32)));
    cs = as_ansi(b, max_read_count);
    cs.read_count = 2;
    cs.encode_success = true;
    return cs;
}

utf32_to_ansi :: inline (b: *u8, max_read_count := 4) -> Code_Point {
    cs: Code_Point = ---;
    maybe_return_encode_failure(max_read_count < 4);
    utf32 := b.(*u32,force).*;
    maybe_return_encode_failure(!is_ansi(utf32));
    cs = as_ansi(b, max_read_count);
    cs.read_count = 4;
    cs.encode_success = true;
    return cs;
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// types

Text_Encoding :: enum u8 {
    UTF8;
    UTF16;
    UTF32;
    ANSI;
}

Code_Point :: struct {
    bytes: [4]u8 #align 4;
    encoding: Text_Encoding;
    // how many bytes are in the bytes array
    count: s8;
    // how many bytes were read when creating this code point
    read_count: s8; 
    encode_success: bool;

    #place bytes;
        words: [2]u16 = ---;
    #place bytes;
        double_word: u32 = ---;
}

// ---------------------------------------------------------------------------------------------------------------------
#scope_file // ---------------------------------------------------------------------------------------------- SCOPE_FILE
// ---------------------------------------------------------------------------------------------------------------------

maybe_return_encode_failure :: (condition: bool) #expand {
    #if SAFE_TEXT_ENCODING {
        if condition {
            `cs.encode_success = false;
            `return `cs;
        }
    }
}

UTF16_HIGH_SURROGATE_MIN : u32 : 0xd800;
UTF16_HIGH_SURROGATE_MAX : u32 : 0xdbff;
UTF16_LOW_SURROGATE_MIN : u32 : 0xdc00;
UTF16_LOW_SURROGATE_MAX : u32 : 0xdfff;
UTF16_HIGH_MASK : u32 : #run (0x3ff << 10).(u32);
UTF16_LOW_MASK : u32 : #run (0x3ff).(u32);

Utf16_Word :: enum u8 {
    BASIC_MULTILINGUAL_PLANE;
    HIGH_SURROGATE;
    LOW_SURROGATE;
}
