
// OBJ doesn't guarantee a winding order. just have to know.
load_obj_file :: (file_path: string, flip_winding: bool) -> []Mesh_Vertex, Index_Buffer {
    data := read_entire_file(file_path);
    defer free(data);

    Mesh_Data_Counts :: struct {
        vertex_count: u32;
        triangle_count: u32;
        max_index: u32;
        quads: bool;
    };

    counter := (line: *string, line_index: s64, counts_void: *void) {
        if line.count < 2 {
            return;
        }
        counts := counts_void.(*Mesh_Data_Counts);

        c0 := to_lower(line.*[0]);
        c1 := to_lower(line.*[1]);
        line.data += 2;
        line.count -= 2;

        if c0 == #char "v" && c1 == #char " " { // vertex
            counts.vertex_count += 1;
        } else if c0 == #char "f" && c1 == #char " " { // face/triangle
            scope_set_allocator(temp);
            auto_release_temp();

            face_component_count := 0;
            face := tokenize_and_trim(line.*, #char " ");

            for face {
                indices := tokenize_and_trim(it, cast(u8)(#char "/"));
                for indices {
                    val, success := parse_int(*it);
                    val -= 1;
                    if !success {
                        continue;
                    }
                    face_component_count += 1;
                    counts.max_index = max(counts.max_index, val.(u32));
                    break;
                }
            }
            if face_component_count == 3 {
                counts.triangle_count += 1;
            } else if face_component_count == 4 {
                counts.triangle_count += 2;
                counts.quads = true;
            } else {
                assert(false);
            }
        }
    }

    counts: Mesh_Data_Counts;
    line_ct := process_per_line(data, counter, *counts);

    assert(counts.vertex_count > counts.max_index);
    if counts.vertex_count != counts.max_index + 1 {
        rm_warning("mesh [%]: vertex count [%] does not equal max index + 1 [%]", file_path, counts.vertex_count, counts.max_index+1);
    }

    Temp_Mesh_Data :: struct {
        vertices: []Mesh_Vertex;
        indices: Index_Buffer;
        vertex_count: s64;
        index_count: s64;
        quads: bool;
    }
    temp_mesh_data: Temp_Mesh_Data;
    temp_mesh_data.quads = counts.quads;

    {
        using temp_mesh_data;
        vertices = alloc_array(Mesh_Vertex, xx counts.vertex_count);
        if counts.max_index > U16_MAX {
            indices.type = .U32;
            indices._u32 = alloc_array(u32, xx (counts.triangle_count * 3));
        } else {
            indices.type = .U16;
            indices._u16 = alloc_array(u16, xx (counts.triangle_count * 3));
        }
    }

    collector := (line: *string, line_index: s64, mesh_data_v: *void) {
        if line.count < 2 {
            return;
        }
        mesh_data := mesh_data_v.(*Temp_Mesh_Data);

        c0 := to_lower(line.*[0]);
        c1 := to_lower(line.*[1]);
        line.data += 2;
        line.count -= 2;

        if c0 == #char "v" && c1 == #char " " { // vertex
            components := tokenize_and_trim(line.*, xx #char " ");
            vertex := *mesh_data.vertices[mesh_data.vertex_count];
            mesh_data.vertex_count += 1;
            cmp_idx := 0;
            for components {
                val, success := parse_float(*it);
                if success {
                    vertex.position.component[cmp_idx] = val;
                    cmp_idx += 1;
                }
            }
        } else if c0 == #char "f" && c1 == #char " " { // face/triangle
            face := tokenize_and_trim(line.*, #char " ");
            face_i := 0;
            for face {
                indices := tokenize_and_trim(it, cast(u8)(#char "/"));
                index := -1;
                for indices {
                    val, success := parse_int(*it, s64); // obj is 1-indexed
                    val -= 1;
                    if !success {
                        continue;
                    }
                    assert(val >= 0);
                    index = val;
                    break;
                }
                if index == -1 {
                    continue;
                }
                if face_i < 3 {
                    if face_i == 0 {
                        assert(mesh_data.index_count % 3 == 0);
                    }
                    if mesh_data.indices.type == .U16 {
                        mesh_data.indices._u16[mesh_data.index_count] = xx index;
                    } else {
                        mesh_data.indices._u32[mesh_data.index_count] = xx index;
                    }
                    mesh_data.index_count += 1;
                } else {
                    // triangulizing the quad
                    assert(mesh_data.quads);
                    assert(face_i == 3);
                    assert(mesh_data.index_count % 3 == 0);
                    if mesh_data.indices.type == .U16 {
                        mesh_data.indices._u16[mesh_data.index_count+0] = mesh_data.indices._u16[mesh_data.index_count-3];
                        mesh_data.indices._u16[mesh_data.index_count+1] = mesh_data.indices._u16[mesh_data.index_count-1];
                        mesh_data.indices._u16[mesh_data.index_count+2] = xx index;
                    } else {
                        mesh_data.indices._u32[mesh_data.index_count+0] = mesh_data.indices._u32[mesh_data.index_count-3];
                        mesh_data.indices._u32[mesh_data.index_count+1] = mesh_data.indices._u32[mesh_data.index_count-1];
                        mesh_data.indices._u32[mesh_data.index_count+2] = xx index;
                    }
                    mesh_data.index_count += 3;
                }
                face_i += 1;
            }
        }
    }

    process_per_line(data, collector, *temp_mesh_data);

    {
        using temp_mesh_data;
        vertices.count = vertex_count;
        if indices.type == .U16 {
            indices._u16.count = index_count;
        } else {
            indices._u32.count = index_count;
        }

        if flip_winding {
            i := 0;
            if indices.type == .U16 {
                while i+1 < indices._u16.count {
                    indices._u16[i], indices._u16[i+1] = indices._u16[i+1], indices._u16[i];
                    i += 3;
                }
            } else {
                while i+1 < indices._u32.count {
                    indices._u32[i], indices._u32[i+1] = indices._u32[i+1], indices._u32[i];
                    i += 3;
                }
            }
        }
    }

    return temp_mesh_data.vertices, temp_mesh_data.indices;
}