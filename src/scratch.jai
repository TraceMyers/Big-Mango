
scratch_init_game :: () {
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
    // cube mesh
    {
        cube_mesh = create_mesh("_cube", cube_vertices, cube_indices);
        cube_mesh.albedo.tint = .{1,1,1,1};
    }
    // character / character mesh
    {
        entity_ref := spawn_entity(.STATIC_MESH, physics_properties_template=.BOX_MAN);
        entity_phys_props := get_entity_physics_properties(xx entity_ref.index);
        // assert(entity_phys_props.body_collider.type == .BOX);

        reorient_mesh_quat: Quaternion;
        set_orientation(*reorient_mesh_quat, .{0,0,1}, .{0,1,0});
        mesh := load_mesh("experimental/FinalBaseMesh.obj", true, reorient_mesh_quat);
        mesh.albedo.tint = .{0.7,0.7,0.9,1.0};
        mesh.albedo.type = .CONSTANT;

        using entity_phys_props;
        // capsule_mesh := get_capsule_mesh(body_collider.height, body_collider.capsule.radius);
        // capsule_mesh.albedo.tint = .{0.6, 0.1, 0.9, 0.5};
        // capsule_mesh.albedo.type = .CONSTANT;
        cube_mesh := load_mesh("_cube");

        set_entity_meshes(entity_ref, .{.BODY, mesh}, .{.BOX_COLLIDER, cube_mesh});
        get_entity(*player_character, entity_ref);
    }
    // npc 
    {
        entity_ref := spawn_entity(.STATIC_MESH, physics_properties_template=.BOX_MAN, make_physics_properties_dynamic=true);
        mesh := load_mesh("experimental/FinalBaseMesh.obj");
        npc := array_add(*npcs);
        entity_phys_props := get_entity_physics_properties(xx entity_ref.index);
        
        using entity_phys_props;
        body_collider.height += 3.0;
        body_collider.box.length = 20.0;
        // body_collider.height *= 0.5;
        // body_collider.capsule.radius *= 2.0;
        // capsule_mesh := get_capsule_mesh(body_collider.height, body_collider.capsule.radius);
        cube_mesh := load_mesh("_cube");

        set_entity_meshes(entity_ref, .{.BODY, mesh}, .{.BOX_COLLIDER, cube_mesh});
        get_entity(npc, entity_ref);
        npc.position = .{40,0,0};
    }
    {
        free_fly_entity = *camera;
        character_entity = *player_character;
        camera_entity = *camera;
    }
}