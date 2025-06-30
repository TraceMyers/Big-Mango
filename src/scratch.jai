
scratch_init_game :: () {
    // set_capacity(*static_mesh_entities, 1024);

    // camera init
    {
        // temp camera stuff;
        camera_ref := spawn_entity(.CAMERA);
        get_entity(*camera, camera_ref);

        camera.camera.* = camera_make(.ORTHOGRAPHIC);
        camera.orthographic.scale = 10.0;

        // camera.camera.* = camera_make(.PERSPECTIVE);

        // camera.position.y = -30.0;
        camera.position.z = 60.0;

        cos_t := cos(PI/4);
        sin_t := sin(PI/4);

        // set_orientation(*camera, .{0,0,-1}, .{0,1,0});
        set_orientation(*camera, .{0,sin_t,-cos_t}, .{0,cos_t,sin_t});
        // rotate(*camera, .{0,0,1}, PI/4);
    }
    man_mesh_index: s64;
    // character / character mesh
    {
        auto_release_temp();

        entity_ref := spawn_entity(.STATIC_MESH);
        man_mesh_index := request_item(*mesh_pool);
        mesh := *mesh_pool[man_mesh_index];

        mesh.albedo.tint = .{0.7,0.7,0.9,0.5};
        mesh.albedo.type = .CONSTANT;

        reorient_mesh_quat: Quaternion;
        set_orientation(*reorient_mesh_quat, .{0,0,1}, .{0,1,0});
        vertices, indices := load_obj_file("../content/experimental/FinalBaseMesh.obj", true, reorient_mesh_quat, temp);

        modified_vertices: [..]Mesh_Vertex;
        modified_vertices.allocator = temp;

        if indices.type == .U16 {
            setup_mesh_data_for_flat_shading(vertices, indices._u16, *modified_vertices);
            create_mesh_data_buffer(*mesh.ibo, indices._u16, .INDEX);
        } else {
            setup_mesh_data_for_flat_shading(vertices, indices._u32, *modified_vertices);
            create_mesh_data_buffer(*mesh.ibo, indices._u32, .INDEX);
        }

        create_mesh_data_buffer(*mesh.vbo, modified_vertices, .VERTEX);

        // todo: maybe auto-gen capsule from a bounding box on the mesh just for ease of use
        capsule_indices: [..]u16;
        capsule_indices.allocator = temp;
        capsule_vertices: [..]Mesh_Vertex;
        capsule_vertices.allocator = temp;
        {
            temp_verts: [..]Mesh_Vertex;
            temp_verts.allocator = temp;
            generate_capsule_geo(*temp_verts, *capsule_indices, 21.5, 3.0, 1.0);
            for *temp_verts {
                it.position += WORLD_UP * 10.0;
            }
            setup_mesh_data_for_flat_shading(temp_verts, capsule_indices, *capsule_vertices);
        }

        capsule_mesh_index := request_item(*mesh_pool);
        capsule_mesh := *mesh_pool[capsule_mesh_index];
        capsule_mesh.albedo.tint = .{0.6, 0.1, 0.9, 0.8};
        capsule_mesh.albedo.type = .CONSTANT;

        create_mesh_data_buffer(*capsule_mesh.vbo, capsule_vertices, .VERTEX);
        create_mesh_data_buffer(*capsule_mesh.ibo, capsule_indices, .INDEX);

        set_entity_meshes(entity_ref, .{.BODY, mesh}, .{.COLLIDER, capsule_mesh});

        get_entity(*player_character, entity_ref);
    }
    // npc 
    {
        auto_release_temp();

        entity_ref := spawn_entity(.STATIC_MESH);
        mesh := *mesh_pool[man_mesh_index];

        set_entity_meshes(entity_ref, .{.BODY, mesh});
        npc := array_add(*npcs);
        get_entity(npc, entity_ref);

        mesh.albedo.tint = .{0.7,0.7,0.9,1.0};

        reorient_mesh_quat: Quaternion;
        set_orientation(*reorient_mesh_quat, .{0,0,1}, .{0,1,0});
        vertices, indices := load_obj_file("../content/experimental/FinalBaseMesh.obj", true, reorient_mesh_quat, temp);

        modified_vertices: [..]Mesh_Vertex;
        modified_vertices.allocator = temp;

        if indices.type == .U16 {
            setup_mesh_data_for_flat_shading(vertices, indices._u16, *modified_vertices);
            create_mesh_data_buffer(*mesh.ibo, indices._u16, .INDEX);
        } else {
            setup_mesh_data_for_flat_shading(vertices, indices._u32, *modified_vertices);
            create_mesh_data_buffer(*mesh.ibo, indices._u32, .INDEX);
        }

        create_mesh_data_buffer(*mesh.vbo, modified_vertices, .VERTEX);

        mesh.albedo.type = .CONSTANT;
    }
    // floor cube mesh
    {
        auto_release_temp();

        cube_mesh = xx request_item(*mesh_pool);

        m1 := *mesh_pool[cube_mesh];
        m1.albedo.tint = .{1,1,1,1};

        modified_vertices: [..]Mesh_Vertex;
        defer array_reset(*modified_vertices);

        setup_mesh_data_for_flat_shading(cube_vertices, cube_indices, *modified_vertices);
        create_mesh_data_buffer(*m1.ibo, cube_indices, .INDEX);
        create_mesh_data_buffer(*m1.vbo, modified_vertices, .VERTEX);
    }
}