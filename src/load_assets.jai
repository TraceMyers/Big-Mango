// $todo: binary mesh format:
// - header says "read 10k verts" -> then 10k verts follow (simple, no parsing except for headers)
// - multithreading: have a table at the top that tells each thread where to begin reading and how much to read. essentially, encode jobs into a header.
// - save_mgo_file :: ()

// OBJ doesn't guarantee or communicate a winding order. just have to know.
load_obj_file :: (asset_path: string, flip_winding: bool, reorientation := QUATERNION_IDENTITY, norm_translation_offsets := Vector3.{}, allocator := context.allocator) -> []Mesh_Vertex, Index_Buffer {
    // ---

    Temp_Mesh_Data :: struct {
        vertices: [..]Mesh_Vertex;
        indices: [..]u32;
        vertex_position_max: Vector3;
        reorientation_quat: Quaternion;
        quads: bool;
        reorient: bool;
        calc_vertex_position_max: bool;
        flip_tri_winding: bool;
        seeking_vertex_start_point := true;
        seeking_index_start_point := true;
    }

    // ---

    collector :: (line: *string, line_index: s64, mesh_data_v: *void) -> bool {
        if line.count < 2 {
            return true;
        }
        mesh_data := mesh_data_v.(*Temp_Mesh_Data);

        c0 := to_lower(line.*[0]);
        c1 := to_lower(line.*[1]);
        line.data += 2;
        line.count -= 2;

        if c0 == #char "v" && c1 == #char " " { // vertex
            vertex := array_add(*mesh_data.vertices);
            cmp_idx := 0;
            float_str : string;

            for c : line.* {
                if c == #char " " {
                    if float_str.data != null {
                        float_str.count = (line.data + it_index) - float_str.data;
                    } else {
                        continue;
                    }
                } else {
                    if float_str.data == null {
                        float_str.data = (line.data + it_index);
                    }
                    if it_index != line.count-1 {
                        continue;
                    }
                }

                pre_decimal: s64;
                post_decimal: s64;
                sign : float = 1.0;
                start_index: s64;
                if float_str[0] == #char "-" {
                    sign = -1.0;
                    start_index = 1;
                }
                found_decimal: bool;
                post_decimal_pow10 : s64 = 1;
                for start_index..float_str.count-1 {
                    c := float_str[it];
                    if c == #char "." {
                        found_decimal = true;
                        continue;
                    }
                    digit := c - 48;
                    if found_decimal {
                        post_decimal = post_decimal * 10 + digit;
                        post_decimal_pow10 *= 10;
                    } else {
                        pre_decimal = pre_decimal * 10 + digit;
                    }
                }

                float_str.data = null;
                val: float = pre_decimal.(float) + post_decimal.(float) / post_decimal_pow10;
                val *= sign;
                vertex.position.component[cmp_idx] = val;
                cmp_idx += 1;
            }

            if mesh_data.calc_vertex_position_max {
                mesh_data.vertex_position_max = max(mesh_data.vertex_position_max, vertex.position);
            }
            if mesh_data.reorient {
                // inlined quat rotation (likely small effect)
                t := cross_product(mesh_data.reorientation_quat.xyz, vertex.position) * 2.0;
                vertex.position = vertex.position + t * mesh_data.reorientation_quat.w + cross_product(mesh_data.reorientation_quat.xyz, t);
            }
        } else if c0 == #char "f" && c1 == #char " " { // face
            val : s64;
            pos : s64;
            face_i : s64;
            seeking_space : bool;

            prev_index_count := mesh_data.indices.count;
            array_resize(*mesh_data.indices, mesh_data.indices.count+3);

            while pos < line.count {
                line_char := line.*[pos];
                pos += 1;
                if seeking_space {
                    if line_char == #char " " {
                        seeking_space = false;
                    }
                    continue;
                } else if line_char >= #char "0" && line_char <= #char "9" {
                    // first number (in pattern #//#//# or #/#/#) is the position index
                    val = val * 10 + (line_char - #char "0");
                    if pos < line.count {
                        continue;
                    }
                } else if val == 0 {
                    continue;
                }

                assert(val >= 1);
                index := val - 1; // obj is 1-indexed
                val = 0;
                seeking_space = line_char != #char " ";

                if face_i < 3 {
                    if mesh_data.flip_tri_winding {
                        if face_i == {
                        case 0;
                            mesh_data.indices[prev_index_count+1] = xx index;
                        case 1;
                            mesh_data.indices[prev_index_count+0] = xx index;
                        case 2;
                            mesh_data.indices[prev_index_count+2] = xx index;
                        }
                    } else {
                        mesh_data.indices[prev_index_count+face_i] = xx index;
                    }
                } else {
                    // triangulizing the quad = use the final vertex + 2 of the previous verts
                    assert(face_i == 3);
                    assert(mesh_data.indices.count % 3 == 0);
                    array_resize(*mesh_data.indices, mesh_data.indices.count+3);
                    if mesh_data.flip_tri_winding {
                        mesh_data.indices[prev_index_count+3] = mesh_data.indices[prev_index_count+2];
                        mesh_data.indices[prev_index_count+4] = mesh_data.indices[prev_index_count+1];
                        mesh_data.indices[prev_index_count+5] = xx index;
                    } else {
                        mesh_data.indices[prev_index_count+3] = mesh_data.indices[prev_index_count+0];
                        mesh_data.indices[prev_index_count+4] = mesh_data.indices[prev_index_count+2];
                        mesh_data.indices[prev_index_count+5] = xx index;
                    }
                }
                face_i += 1;
            }
        }
        return true;
    }

    // ---

    scope_timer();
    begin_time := seconds_since_init();

    scope_set_working_directory("../assets");
    data : string;
    {
        scope_timer("load file");
        data = read_entire_file(asset_path);
    }
    defer free(data);

    FILE_SIZE_MIN_FOR_ESTIMATION :: 1_200_000; // ~1.2MB
    file_size := max(data.count, FILE_SIZE_MIN_FOR_ESTIMATION); // vertex bias is negative. need to overcome the bias.
    OVERESTIMATION_FACTOR :: 1.1;

    // based on linear regression with n=3 samples. not great, but it's something
    // $todo: estimate coefficients with n > 30 samples covering a good range of sizes, alpha = 0.025
    vertex_bias := -21_492.37;
    vertex_coef := 0.024554;
    vertex_count_estimate := ((vertex_bias + vertex_coef * file_size.(float)) * OVERESTIMATION_FACTOR).(s64);

    index_bias := 11_386.34;
    index_coef := 0.047907;
    index_count_estimate := ((index_bias + index_coef * file_size.(float)) * OVERESTIMATION_FACTOR).(s64);

    temp_mesh_data: Temp_Mesh_Data;
    {
        using temp_mesh_data;
        reorient = reorientation != QUATERNION_IDENTITY;
        reorientation_quat = reorientation;
        vertices.allocator = allocator;
        indices.allocator = allocator;
        array_reserve(*vertices, vertex_count_estimate);
        array_reserve(*indices, index_count_estimate);
        calc_vertex_position_max = norm_translation_offsets != .{};
        vertex_position_max = .{};
        flip_tri_winding = flip_winding;
    }

    {
        scope_timer("gather data");
        process_per_line(data, collector, *temp_mesh_data);
    }

    {
        scope_timer("translate vertex positions");
        if temp_mesh_data.calc_vertex_position_max {
            offset := norm_translation_offsets * temp_mesh_data.vertex_position_max;
            for *temp_mesh_data.vertices {
                it.position += offset;
            }
        }
    }

    {
        scope_timer("shrink arrays");
        array_shrink_if_small_enough(*temp_mesh_data.vertices, 0.85);
        array_shrink_if_small_enough(*temp_mesh_data.indices, 0.85);
    }

    // $todo: u16 indices, probably best to make 'allow_u16' an option. this makes it so any stuff coming after this function that might add more vertices (like setup for flat shading), can wait until checking if it can be made into a u16 index array.
    out_index_buffer: Index_Buffer;
    out_index_buffer.type = .U32;
    out_index_buffer._u32 = temp_mesh_data.indices;

    end_time := seconds_since_init();
    time_spent_loading := end_time - begin_time;

    rm_log("loaded obj at %, file size: % KB. vertex count: %, tri count: %. time taken: % ms", asset_path, data.count / 1024, temp_mesh_data.vertices.count, temp_mesh_data.indices.count / 3, time_spent_loading * 1000.0);

    return temp_mesh_data.vertices, out_index_buffer;
}

// https://code.blender.org/2013/08/fbx-binary-file-format-specification/
// https://gist.github.com/iscle/0dbcee58be8582978d15ea3629ce3e8b
// todo: text-based file specification
load_fbx_file :: (file_path: string, allocator := context.allocator) {
    auto_release_temp();
    reader: Serializer(.STATIC, .BYTE);
    reader.memory = read_entire_file(file_path);
    defer reset(*reader.memory);
    reader.read_array_allocator = temp;
    set_rw_mode(*reader, .READ);

    if reader.memory.count < 26 {
        rm_warning("file length too short.");
        return;
    }

    BINARY_HEADER_MAGIC :: "Kaydara FBX Binary  "; // null-terminated
    binary_header_magic_with_null := BINARY_HEADER_MAGIC;
    binary_header_magic_with_null.count += 1;

    file_header_magic: string;
    read_string(*reader, *file_header_magic);
    if file_header_magic != binary_header_magic_with_null {
        head_str := string.{BINARY_HEADER_MAGIC.count, reader.memory.data};
        rm_warning("the first bytes of the file, '%' do not match '%'", head_str, BINARY_HEADER_MAGIC);
        return;
    }

    if read_out(*reader, u8) != 0x1a {
        rm_warning("header bytes maybe not correct for unknown spec");
    }

    e : Endianness = ifx read_out(*reader, u8) == 0 then .LITTLE else .BIG;
    // todo: maybe support? probably not, right?
    assert(e == .LITTLE);
    
    version := read_out(*reader, u32);

    FBX_Property_Type :: enum u8 {
        BOOL::1;
        U8;
        S16;
        S32;
        S64;
        F32;
        F64;
        BOOL_ARRAY;
        U8_ARRAY;
        S16_ARRAY;
        S32_ARRAY;
        S64_ARRAY;
        F32_ARRAY;
        F64_ARRAY;
    }

    FBX_Property :: struct {
        type: FBX_Property_Type;
        value: union {
            _bool: bool;
            _u8: u8;
            _s16: s16;
            _s32: s32;
            _s64: s64;
            _f32: float32;
            _f64: float64;
            _bool_array:[]bool;
            _u8_array:  []u8;
            _s16_array: []s16;
            _s32_array: []s32;
            _s64_array: []s64;
            _f32_array: []float32;
            _f64_array: []float64;
        }
    }

    set_fbx_property_value :: (prop: *FBX_Property, type: FBX_Property_Type, value: *void, array_count: s64=0) {
        assert(prop.type == 0);
        prop.type = type;
        if type == {
        case .BOOL;
            prop.value._bool = value.(*bool).*;
        case .U8;
            prop.value._u8 = value.(*u8).*;
        case .S16;
            prop.value._s16 = value.(*s16).*;
        case .S32;
            prop.value._s32 = value.(*s32).*;
        case .S64;
            prop.value._s64 = value.(*s64).*;
        case .F32;
            prop.value._f32 = value.(*float32).*;
        case .F64;
            prop.value._f64 = value.(*float64).*;
        case .BOOL_ARRAY;
            prop.value._bool_array.data = value.(*[]bool).data;
            prop.value._bool_array.count = array_count;
        case .U8_ARRAY;
            prop.value._u8_array.data = value.(*[]u8).data;
            prop.value._u8_array.count = array_count;
        case .S16_ARRAY;
            prop.value._s16_array.data = value.(*[]s16).data;
            prop.value._s16_array.count = array_count;
        case .S32_ARRAY;
            prop.value._s32_array.data = value.(*[]s32).data;
            prop.value._s32_array.count = array_count;
        case .S64_ARRAY;
            prop.value._s64_array.data = value.(*[]s64).data;
            prop.value._s64_array.count = array_count;
        case .F32_ARRAY;
            prop.value._f32_array.data = value.(*[]float32).data;
            prop.value._f32_array.count = array_count;
        case .F64_ARRAY;
            prop.value._f64_array.data = value.(*[]float64).data;
            prop.value._f64_array.count = array_count;
        case;
            assert(false, "invalid fbx property value type");
        }
    }

    FBX_Node :: struct {
        children: []FBX_Node;
        properties: []FBX_Property;
        name: string;
    }

    is_null :: (using node: *FBX_Node) -> bool {
        return children.count == 0 && properties.count == 0 && name.count == 0;
    }

    prop_array_element_type :: inline (type: u8) -> u8 {
        assert(type >= #char "Z");
        return type - (#char "a" - #char "A");
    }

    prop_enum_type :: (type: u8) -> FBX_Property_Type {
        if type < #char "Z" {
            if type == {
            case #char "Y";
                return .S16;
            case #char "C"; #through;
            case #char "B";
                return .U8;
            case #char "I";
                return .S32;
            case #char "L";
                return .S64;
            case #char "F";
                return .F32;
            case #char "D";
                return .F64;
            case #char "S"; #through;
            case #char "R";
                return .U8_ARRAY;
            case;
                assert(false, "invalid property value type");
            }
            return 0;
        } 
        array_element_type := min(prop_array_element_type(type), #char "Y");
        if array_element_type == {
        case #char "Y";
            return .S16_ARRAY;
        case #char "C"; #through;
        case #char "B";
            return .U8_ARRAY;
        case #char "I";
            return .S32_ARRAY;
        case #char "L";
            return .S64_ARRAY;
        case #char "F";
            return .F32_ARRAY;
        case #char "D";
            return .F64_ARRAY;
        case;
            assert(false, "invalid property value type");
        }
        return 0;
    }

    prop_element_size :: inline (type: u8) -> u8 {
        if type == {
        case #char "Y";
            return 2;
        case #char "C"; #through;
        case #char "B";
            return 1;
        case #char "I";
            return 4;
        case #char "L";
            return 8;
        case #char "F";
            return 4;
        case #char "D";
            return 8;
        case;
            assert(false, "invalid property value type");
        }
        return 0;
    }

    read_fbx_property :: (reader: *Serializer(.STATIC, .BYTE), prop: *FBX_Property, e: Endianness) -> bool {
        type := read_out(reader, u8);
        if type == #char "S" || type == #char "R" {
            // string / raw bytes
            byte_count := read_out(reader, u32);
            assert(byte_count > 0);
            array := alloc_array(u8, byte_count, temp);
            read_array_data(reader, *array, xx array.count);
            set_fbx_property_value(prop, .U8_ARRAY, *array);
        } else if type < #char "Z" {
            // primitive value
            if type == {
            case #char "Y";
                val := read_out(reader, s16);
                set_fbx_property_value(prop, .S16, *val);
            case #char "C";
                val := read_out(reader, u8);
                set_fbx_property_value(prop, .U8, *val);
            case #char "B";
                val := read_out(reader, u8) != 0;
                set_fbx_property_value(prop, .BOOL, *val);
            case #char "I";
                val := read_out(reader, s32);
                set_fbx_property_value(prop, .S32, *val);
            case #char "L";
                val := read_out(reader, s64);
                set_fbx_property_value(prop, .S64, *val);
            case #char "F";
                val := read_out(reader, float32);
                set_fbx_property_value(prop, .F32, *val);
            case #char "D";
                val := read_out(reader, float64);
                set_fbx_property_value(prop, .F64, *val);
            case;
                assert(false, "invalid property value type");
            }
        } else {
            // array
            array_count := read_out(reader, u32);
            // 0 = uncompressed, 1 = zlib compressed
            encoding := read_out(reader, u32) != 0;
            compressed_size := read_out(reader, u32);

            element_size := prop_element_size(prop_array_element_type(type));
            decompressed_size := element_size * array_count;
            
            // note that this needs to be aligned to 8 bytes, and I believe every allocation using the default & temp allocators is aligned to 8.
            decompressed_buffer: []u8;

            if encoding {
                auto_release_temp();
                
                compressed_buffer: []u8;
                read_array_data(reader, *compressed_buffer, xx compressed_size);

                actual_size : u32 = decompressed_size;
                result := Zlib.uncompress(decompressed_buffer.data, *actual_size, compressed_buffer.data, compressed_size);

                if result != Zlib.Z_OK {
                    rm_error("failed to decompress, array type %", prop_array_element_type(type));
                    return false;
                }
                if actual_size != decompressed_size {
                    rm_warning("expected property size %, got size %", decompressed_size, actual_size);
                }

                set_fbx_property_value(prop, prop_enum_type(type), *decompressed_buffer, xx array_count);
            } else {
                read_array_data(reader, *decompressed_buffer, xx decompressed_size);
                set_fbx_property_value(prop, prop_enum_type(type), *decompressed_buffer, xx array_count);
            }
        }
        return true;
    }

    nodes: [..]FBX_Node;
    nodes.allocator = temp;
    array_reserve(*nodes, 128);

    failure: bool;
    finished_load : bool;
    while !finished_load {
        node: FBX_Node;

        end_offset          := read_out(*reader, u32);
        property_count      := read_out(*reader, u32);
        property_list_count := read_out(*reader, u32);
        name_length         := read_out(*reader, u8);
        bytes : u32 = name_length;

        if property_count > 0 {
            node.properties = alloc_array(FBX_Property, xx property_count, temp);
            for *node.properties {
                if !read_fbx_property(*reader, it, e) {
                    failure = true;
                    finished_load = true;
                    break;
                }
            }
        }

        if is_null(*node) {
            break;
        }
        array_add(*nodes, node);
    }
}

// ---------------------------------------------------------------------------------------------------------------------
#scope_file // ---------------------------------------------------------------------------------------------- SCOPE_FILE
// ---------------------------------------------------------------------------------------------------------------------
