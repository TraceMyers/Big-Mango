// $todo: binary mesh format:
// - header says "read 10k verts" -> then 10k verts follow (simple, no parsing except for headers)
// - multithreading: have a table at the top that tells each thread where to begin reading and how much to read. essentially, encode jobs into a header.
// - save_mgo_file :: ()

GOM_FILE_SIZE_MAX :: 100 * 1024 * 1024;

Gom_Package_Type :: enum u8 {
    MESH :: 1;
    SKINNED_MESH;
}

// $todo: no concept of mesh sections or so many things...
Gom_Package :: struct {
    type: Gom_Package_Type;
    vertices: []Mesh_Vertex;
    indices: Index_Buffer;
    skeleton: *Skeleton;
}

// save :: #bake_arguments save_or_load_mgosm_file(rw_mode=.WRITE);
// load :: #bake_arguments save_or_load_mgosm_file(rw_mode=.READ);
load_skinned_mesh :: (asset_path: string, package: *Gom_Package, load_allocator := context.allocator) -> bool {
    // ---

    HeaderInfo :: struct {
        record: *Serializer(.STATIC);
        joint_count: u32;
        vertex_count: u32;
        triangle_count: u32;
        joint_names_begin: u32;
        joint_transforms_begin: u32;
        joint_parents_begin: u32;
        vertices_begin: u32;
        triangles_begin: u32;
        data_position: u32;
        line_count: u32;
        format_version: u32;
        read_success := true;
    }

    // ---

    parse_header_line :: (line: *string, line_index: s64, header_info_voidptr: *void) -> bool {
        using header_info := header_info_voidptr.(*HeaderInfo);

        return_failure_if :: (value: bool) #expand {
            if value {
                `read_success = false;
                `return false;
            }
        }

        tokens := split(line.*, ":");
        for *token : tokens {
            token.* = trim(token.*);
        }
        line_count = xx (line_index + 1);

        if line_index == {
        case 0;
            return_failure_if(tokens.count != 3);
            return_failure_if(tokens[0] != "mgo");
            return_failure_if(tokens[1] != "skinned mesh");
            version_tokens := split(tokens[2], " ");
            return_failure_if(version_tokens.count != 2);
            return_failure_if(version_tokens[0] != "version");
            format_version=, success := parse_int(*version_tokens[1], u32);
            return_failure_if(!success);
        case 1;
            return_failure_if(tokens.count != 2);

            return_failure_if(tokens[0] != "joints");
            joint_count=, success := parse_int(*tokens[1], u32);
            return_failure_if(!success);
        case 2;
            return_failure_if(tokens.count != 2);
            return_failure_if(tokens[0] != "vertices");
            vertex_count=, success := parse_int(*tokens[1], u32);
            return_failure_if(!success);
        case 3;
            return_failure_if(tokens.count != 2);
            return_failure_if(tokens[0] != "triangles");
            triangle_count=, success := parse_int(*tokens[1], u32);
            return_failure_if(!success);
        case 4;
            align_4_remainder := 4 - (data_position & 0x3);
            number_string := string.{line.count-align_4_remainder, line.data + align_4_remainder};
            // should be left with a 4 byte number - the offset to joint transforms
            return_failure_if(number_string.count != 4);
            // joint transforms begin after the names, at a point in the file marked here
            // will be useful to use multithreading to read lots of these files in quickly
            joint_transforms_begin = (number_string[3].(u32) << 24) | (number_string[2].(u32) << 16) | (number_string[1].(u32) << 8) | (number_string[0].(u32));
            // joint names begin immediately after the header. 4 byte alignment, 4 bytes space (always there). 1 byte newline.
            joint_names_begin = data_position + align_4_remainder + 4 + 1;
            // the rest of the data positions can be inferred from here
            JOINT_TRANSFORM_SIZE :: size_of(Matrix4);
            JOINT_PARENT_SIZE    :: size_of(s16);
            POSITION_SIZE        :: size_of(Vector3);
            NORMAL_SIZE          :: size_of(Vector3);
            WEIGHTS_SIZE         :: size_of(Vector3);
            JOINT_IDS_SIZE       :: size_of(s16) * 4;
            VERTEX_SIZE          :: POSITION_SIZE + NORMAL_SIZE + WEIGHTS_SIZE + JOINT_IDS_SIZE;
            TRIANGLE_SIZE        :: size_of(u32) * 3;

            joint_transforms_size := JOINT_TRANSFORM_SIZE * joint_count;
            joint_parents_begin = joint_transforms_begin + joint_transforms_size;

            joint_parents_size := JOINT_PARENT_SIZE * joint_count;
            joint_parents_end := joint_parents_begin + joint_parents_size;
            align_4_remainder = 4 - (joint_parents_end & 0x3);
            vertices_begin = joint_parents_end + align_4_remainder;

            vertices_size := VERTEX_SIZE * vertex_count;
            triangles_begin = vertices_begin + vertices_size; 

            triangles_size := TRIANGLE_SIZE * triangle_count;
            eof_location := triangles_begin + triangles_size;

            file_size := record.memory.count;
            read_success = eof_location == file_size;

            // done reading the header
            return false;
        }

        data_position += xx (line.count + 1); // +1 for newline that was omitted
        return true;
    }

    parse_joint_name :: (line: *string, line_index: s64, joint_names_voidptr: *void) -> bool {
        assert(line.count < 128, "probably incorrectly parsed (length = %) joint name line: %", line.count, line.*);
        joint_names := joint_names_voidptr.(*[]string);
        joint_names.*[line_index] = copy_string(line.*);
        if line_index == joint_names.count-1 {
            // done reading names
            return false;
        }
        return true;
    }

    // ---

    scope_timer();

    record: Serializer(.STATIC);
    set_rw_mode(*record, .READ, true);
    record.memory = read_entire_file(asset_path);

    // $todo: mannequin.mgosm seems to take ~66% of its time just reading the file in, but 33% of 1ms isn't nothing, and it should
    // be easy to roughly calculate how much of the rest of the time is taken up by allocations, and how much faster that
    // might be if using a flat allocator.
    scope_timer("after reading file");

    assert(record.memory.count <= GOM_FILE_SIZE_MAX);
    record.read_array_allocator = load_allocator;

    header_info := HeaderInfo.{record=*record};
    {
        scope_set_allocator(temp);
        auto_release_temp();
        process_per_line(record.memory, parse_header_line, *header_info);
    }

    if !header_info.read_success {
        return false;
    }

    scope_set_allocator(load_allocator);

    // note: this file format was made so that after reading the header, multiple threads could immediately begin to work across different parts of the file. but, i'm just going to read it in serially for now because it's easier. 

    if header_info.format_version == {
    case 1;
        if header_info.joint_count > 0 {
            // joint names
            record.head = xx header_info.joint_names_begin;
            package.skeleton.joint_names = alloc_array(string, header_info.joint_count, load_allocator);
            file_data_beginning_at_joint_names := string.{record.memory.count - record.head, record.memory.data + record.head};
            process_per_line(file_data_beginning_at_joint_names, parse_joint_name, *package.skeleton.joint_names);
            // joint transforms
            record.head = xx header_info.joint_transforms_begin;
            serialize(*record, *package.skeleton.joint_transforms, header_info.joint_count.(s32));
            // joint parents
            record.head = xx header_info.joint_parents_begin;
            serialize(*record, *package.skeleton.joint_parents, header_info.joint_count.(s32));
        }
        // vertices
        record.head = xx header_info.vertices_begin;
        serialize(*record, *package.vertices, header_info.vertex_count.(s32));
        // triangles
        package.indices.type = .U32;
        record.head = xx header_info.triangles_begin;
        serialize(*record, *package.indices._u32, (header_info.triangle_count * 3).(s32));
    case;
        assert(false, "invalid mgosm format version %", header_info.format_version);
    }

    return true;
}

save :: #bake_arguments save_or_load_gom_file(rw_mode=.WRITE);
load :: #bake_arguments save_or_load_gom_file(rw_mode=.READ);
save_or_load_gom_file :: (asset_path: string, package: *Gom_Package, rw_mode: Rw_Mode, load_allocator := context.allocator) {
    __mark := get_temporary_storage_mark();
    defer if rw_mode == .WRITE then set_temporary_storage_mark(__mark);

    begin_time := seconds_since_init();

    record: Serializer(.STATIC);
    set_rw_mode(*record, rw_mode, true);

    if rw_mode == .READ {
        record.memory = read_entire_file(asset_path);
        assert(record.memory.count <= GOM_FILE_SIZE_MAX);
        record.read_array_allocator = load_allocator;
    } else {
        mesh_vertex_size := size_of(Vector3);
        size := mesh_vertex_size * package.vertices.count;
        if package.indices.type == .U16 {
            size += size_of(u16) * package.indices._u16.count;
        } else { // U32
            size += size_of(u32) * package.indices._u32.count;
        }
        size += size_of(s64) * 3; // accounting for array counts and the index type
        size += record.head; // serializer should have made space for a checksum
        assert(size <= GOM_FILE_SIZE_MAX);
        record.memory = .{size, alloc(size,,temp)};
    }

    serialize(*record, (*package.type).(*u8), size_of(Gom_Package_Type));

    if package.type == .SKINNED_MESH {
        serialize(*record, *package.vertices);
    } else if package.type == .MESH {
        serialize(*record, *package.vertices.count);
        if package.vertices.count > 0 {
            align_head_up_for_type(*record, float);
            vector_record := (record.memory.data + record.head).(*Vector3);
            if rw_mode == .READ {
                package.vertices = alloc_array(Mesh_Vertex, package.vertices.count, load_allocator);
                for 0..package.vertices.count-1 {
                    package.vertices[it].position = (vector_record + it).*;
                }
            } else for 0..package.vertices.count-1 {
                (vector_record + it).* = package.vertices[it].position;
            }
            record.head += xx (12 * package.vertices.count);
        }
    } else {
        assert(false, "encountered invalid mesh type % during %", package.type, rw_mode);
    }

    serialize(*record, (*package.indices.type).(*u8), size_of(Mesh_Index_Type));
    if package.indices.type == .U16 {
        serialize(*record, *package.indices._u16);
    } else {
        serialize(*record, *package.indices._u32);
    }

    if package.type == .SKINNED_MESH {
        //
        // serialize(*record, package.skeleton.skeleton_asset_ref.name_hash);
        if rw_mode == .READ {
            // load skeleton asset
        }
    }

    if rw_mode == .WRITE {
        write_entire_file(asset_path, *record);
    }

    end_time := seconds_since_init();
    time_spent_loading := end_time - begin_time;
    operative_word := ifx rw_mode == .READ then "loaded" else "saved";
    rm_log("% mgo at %, file size: % KB. vertex count: %, tri count: %. time taken: % ms", operative_word, asset_path, record.memory.count / 1024, package.vertices.count, package.indices._u16.count / 3, time_spent_loading * 1000.0);
}

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

            pre_decimal: s64;
            post_decimal: s64;
            sign : = 1.0;
            found_decimal: bool;
            post_decimal_pow10 := 1;
            started_parsing_component: bool;

            for c : line.* {
                if c == #char " " {
                    if !started_parsing_component {
                        continue;
                    }
                } else {
                    started_parsing_component = true;
                    if c == #char "-" {
                        sign = -1.0;
                    } else if c == #char "." {
                        found_decimal = true;
                    } else {
                        digit := c - 48;
                        if found_decimal {
                            post_decimal = post_decimal * 10 + digit;
                            post_decimal_pow10 *= 10;
                        } else {
                            pre_decimal = pre_decimal * 10 + digit;
                        }
                    }
                    if it_index != line.count-1 {
                        continue;
                    }
                }

                val: float = pre_decimal.(float) + post_decimal.(float) / post_decimal_pow10;
                val *= sign;
                vertex.position.component[cmp_idx] = val;
                cmp_idx += 1;

                pre_decimal = 0;
                post_decimal = 0;
                sign = 1;
                found_decimal = false;
                post_decimal_pow10 = 1;
                started_parsing_component = false;
            }

            if mesh_data.calc_vertex_position_max {
                mesh_data.vertex_position_max = max(mesh_data.vertex_position_max, vertex.position);
            }
            if mesh_data.reorient {
                // inlined quat rotation (likely small or no effect)
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
    set_rw_mode(*reader, .READ, true);

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
