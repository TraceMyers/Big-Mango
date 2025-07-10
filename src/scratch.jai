

scratch_init_game :: () {
    {
        fixed_delta_time = 1.0 / 60.0;
        // fixed_delta_time = 1.0 / 1000.0;
    }
    // sin_cos test
    {
        // TEST_COUNT :: 16384;
        // inputs: [TEST_COUNT]float32;
        // sin_outputs: [TEST_COUNT]float32;
        // cos_outputs: [TEST_COUNT]float32;
        // sc_sin_outputs: [TEST_COUNT]float32;
        // sc_cos_outputs: [TEST_COUNT]float32;
        // sin_errors: [TEST_COUNT]float32;
        // cos_errors: [TEST_COUNT]float32;
        // max_sin_error := 0.0;
        // max_cos_error := 0.0;
        // sum_sin_error : float64 = 0.0;
        // sum_cos_error : float64 = 0.0;

        // RANGE :: 5_000.0;

        // for *inputs {
        //     it.* = random_get_within_range(-RANGE, RANGE);
        //     sin_outputs[it_index] = sin(it.*);
        //     cos_outputs[it_index] = cos(it.*);
        //     sc_sin_outputs[it_index], sc_cos_outputs[it_index] = sin_cos(it.*);
        //     sin_errors[it_index] = sin_outputs[it_index] - sc_sin_outputs[it_index];
        //     cos_errors[it_index] = cos_outputs[it_index] - sc_cos_outputs[it_index];
        //     max_sin_error = max(abs(sin_errors[it_index]), max_sin_error);
        //     max_cos_error = max(abs(cos_errors[it_index]), max_cos_error);
        //     sum_sin_error += sin_errors[it_index];
        //     sum_cos_error += cos_errors[it_index];
        // }

        // quick_sort(sin_errors, (a, b) => ((a - b) * (100_000).(float64)).(s64));    
        // quick_sort(cos_errors, (a, b) => ((a - b) * (100_000).(float64)).(s64));    

        // avg_sin_error := sum_sin_error / TEST_COUNT.(float64);
        // avg_cos_error := sum_cos_error / TEST_COUNT.(float64);

        // med_sin_error := sin_errors[TEST_COUNT/2];
        // med_cos_error := cos_errors[TEST_COUNT/2];

        // rm_log("sin | error max: %, error avg: %, error med: %", max_sin_error, avg_sin_error, med_sin_error);
        // rm_log("cos | error max: %, error avg: %, error_med: %", max_cos_error, avg_cos_error, med_cos_error);
    }
    // camera init
    {
        // temp camera stuff;
        camera_ref := spawn_entity(.CAMERA, name="camera");
        get_entity(*camera, camera_ref);

        camera.camera.* = camera_make(.ORTHOGRAPHIC);
        camera.orthographic.scale = ortho_scale;

        // camera.camera.* = camera_make(.PERSPECTIVE);

        camera.position.y = -30.0;
        camera.position.z = 60.0;
        cos_t := cos(PI/4);
        sin_t := sin(PI/4);
        set_orientation(*camera, .{0,sin_t,-cos_t}, .{0,cos_t,sin_t});

        // set_orientation(*camera, .{0,1,0}, .{0,0,1});

        // rotate(*camera, .{0,0,1}, PI/4);
    }
    // cube mesh
    {
        cube_mesh = create_mesh("_cube", cube_vertices, cube_indices);
        cube_mesh.albedo.tint = .{1,1,1,1};
    }
    // plane mesh
    {
        plane_mesh = create_mesh("_plane", plane_vertices, plane_indices);
        plane_mesh.albedo.tint = .{1,1,1,1};
    }
    // character / character mesh
    {
        entity_ref := spawn_entity(.STATIC_MESH, name="player", physics_properties_template=.SPHERE_MAN, make_physics_properties_dynamic=true);
        entity_phys_props := get_entity_physics_properties(xx entity_ref.index);
        // entity_phys_props.body_elasticity = 1.0;

        array_add(*physics_debugger_entity_ids, entity_ref.id);
        // physics_debugger_ignore_immovable = true;

        reorient_mesh_quat: Quaternion;
        set_orientation(*reorient_mesh_quat, .{0,0,1}, .{0,1,0});
        mesh := get_or_load_mesh("experimental/FinalBaseMesh.obj", true, reorient_mesh_quat);
        mesh.albedo.tint = .{0.7,0.7,0.9,1.0};
        mesh.albedo.type = .CONSTANT;

        using entity_phys_props;
        capsule_mesh := get_or_create_capsule_mesh(body_collider.sphere.radius*2.0, body_collider.sphere.radius);
        capsule_mesh.albedo.tint = .{0.6, 0.1, 0.9, 0.5};
        capsule_mesh.albedo.type = .CONSTANT;
        mass = 1.0;

        body_elasticity = 0.0;
        // cube_mesh := load_mesh("_cube");

        set_entity_meshes(entity_ref, .{.BODY, mesh}, .{.CAPSULE_COLLIDER, capsule_mesh});
        get_entity(*player_character, entity_ref);
        // set_orientation(*player_character.orientation, .{0,0,1}, .{1,0,0});
        player_character.position.x=40;
        player_character.position.z = 50.0;
    }
    // npc 
    {
        entity_ref := spawn_entity(.STATIC_MESH, name="npc", physics_properties_template=.SPHERE_MAN, make_physics_properties_dynamic=true);
        mesh := get_or_load_mesh("experimental/FinalBaseMesh.obj");
        npc := array_add(*npcs);
        entity_phys_props := get_entity_physics_properties(xx entity_ref.index);

        // array_add(*physics_debugger_entity_ids, entity_ref.id);
        
        using entity_phys_props;
        // body_collider.height += 3.0;
        // body_collider.box.length = 20.0;
        // body_collider.height *= 0.5;
        // body_collider.capsule.radius *= 2.0;
        capsule_mesh := get_or_create_capsule_mesh(body_collider.sphere.radius*2.0, body_collider.sphere.radius);
        // mass = IMMOVABLE_ENTITY_MASS;
        mass = 1.0;
        body_elasticity = 0.0;
        // cube_mesh := load_mesh("_cube");

        set_entity_meshes(entity_ref, .{.BODY, mesh}, .{.CAPSULE_COLLIDER, capsule_mesh});
        get_entity(npc, entity_ref);
        npc.position = .{40,0,2};
    }
    // set experimental global pointers
    {
        free_fly_entity = *camera;
        character_entity = *player_character;
        camera_entity = *camera;
    }
    // ground entity
    {
        entity_ref := spawn_entity(.STATIC_MESH, name="ground", physics_properties_template=.GROUND, make_physics_properties_dynamic=true);
        phys_props := get_entity_physics_properties(xx entity_ref.index);

        {
            using phys_props;
            body_collider.type = .PLANE;
            body_collider.plane.half_height = 50.0;
            body_collider.plane.width = 100.0;
            body_elasticity = 0.01;
            gravity_accel = 0.0;
            mass = IMMOVABLE_ENTITY_MASS;
        }

        set_entity_meshes(entity_ref, .{.PLANE_COLLIDER, plane_mesh});

        get_entity(*ground, entity_ref);
        set_orientation(*ground.orientation, .{0,0,1}, .{1,0,0});
        rotate(*ground, WORLD_FORE, PI/6.0);
        ground.position.z = 0.0;

        // ground.position.x -= phys_props.body_collider.plane.width * 0.5;
        // ground.position.y -= phys_props.body_collider.half_height;
    }
}

scratch_think :: () {
    player_half_height := player_character.physics_properties.body_collider.half_height;
    player_center := player_character.position + Vector3.{z=player_half_height};
    end_pt := project_point_onto_plane(player_character.position, ground.position, .{0,0,1});
}


#scope_file // ------------------------------------------------------------------------------------------------ { FILE }
