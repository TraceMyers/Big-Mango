
Endianness :: enum u8 {
    LITTLE;
    BIG;
}

read_number_from_binary :: inline (bin: string, position: s64, $Number_Type: Type, endianness := Endianness.LITTLE) -> Number_Type 
#modify {
    info := cast(*Type_Info)Number_Type;
    if info.type == .INTEGER || info.type == .FLOAT{
        return info.runtime_size >= 1 && info.runtime_size <= 8;
    }
    return false;
} {
    // backing int type
    #if size_of(Number_Type) == 8 {
        T :: u64;
    } else #if size_of(Number_Type) == 4 {
        T :: u32;
    } else #if size_of(Number_Type) == 2 {
        T :: u16;
    } else {
        T :: u8;
    }

    raw_val: T = ---;
    if endianness == .LITTLE {
        #if size_of(T) == {
        case 8;
            raw_val = (bin[position+0].(T) << 56) | (bin[position+1].(T) << 48) | (bin[position+2].(T) << 40) | (bin[position+3] << 32)
                    | (bin[position+4].(T) << 24) | (bin[position+5].(T) << 16) | (bin[position+6].(T) << 08) | (bin[position+7] << 00);
        case 4;
            raw_val = (bin[position+0].(T) << 24) | (bin[position+1].(T) << 16) | (bin[position+2].(T) << 8) | (bin[position+3]);
        case 2;
            raw_val = (bin[position+1].(T) << 8) | (bin[position+0]);
        case 1;
            raw_val = bin[position+0];
        }
    } else {
        #if size_of(T) == {
        case 8;
            raw_val = (bin[position+0].(T) << 00) | (bin[position+1].(T) << 08) | (bin[position+2].(T) << 16)  | (bin[position+3] << 24)
                    | (bin[position+4].(T) << 32) | (bin[position+5].(T) << 40) | (bin[position+6].(T) << 48)  | (bin[position+7] << 56);
        case 4;
            raw_val = (bin[position+0].(T) << 00) | (bin[position+1].(T) << 08) | (bin[position+2].(T) << 16)  | (bin[position+3] << 24);
        case 2;
            raw_val = (bin[position+0].(T) << 00) | (bin[position+1].(T) << 08);
        case 1;
            raw_val = bin[position+0];
        }
    }

    return (*raw_val).(*Number_Type).*;
}
