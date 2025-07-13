

scratch_init_game :: () {
    {
        fixed_delta_time = 1.0 / 60.0;
        // fixed_delta_time = 1.0 / 1000.0;
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

        set_entity_meshes(entity_ref, .{plane_mesh,.{}});

        get_entity(*ground, entity_ref);
        set_orientation(*ground.orientation, .{0,0,1}, .{1,0,0});
        ground.position.z = 0.0;
    }
    // camera init
    {
        // temp camera stuff;
        camera_ref := spawn_entity(.CAMERA, name="camera");
        get_entity(*camera, camera_ref);
        camera.camera.* = camera_make(.ORTHOGRAPHIC);
    }
    // character / character mesh
    {
        entity_ref := spawn_entity(.STATIC_MESH, name="player", physics_properties_template=.SPHERE_MAN, make_physics_properties_dynamic=true);

        entity_phys_props := get_entity_physics_properties(xx entity_ref.index);
        {
            using entity_phys_props;
            mass = 1.0;
            body_elasticity = 0.0;
        }

        array_add(*physics_debugger_entity_ids, entity_ref.id);

        reorient_mesh_quat: Quaternion;
        set_orientation(*reorient_mesh_quat, .{0,0,1}, .{0,1,0});

        mesh := get_or_load_mesh("experimental/FinalBaseMesh.obj", true, reorient_mesh_quat, .{0,0,-5.0});
        set_entity_meshes(entity_ref, .{mesh, .{tint=.{0.7,0.7,0.9,1.0}}}, .{sphere_mesh_mid_poly, .{tint=.{0.6, 0.1, 0.9, 0.5}}});

        get_entity(*player_character, entity_ref);
        player_character.position.z = 50.0;
    }
    // npc 
    for 0..0
    {
        entity_ref := spawn_entity(.STATIC_MESH, name="npc", physics_properties_template=.SPHERE_MAN, make_physics_properties_dynamic=true);
        npc := array_add(*npcs);

        entity_phys_props := get_entity_physics_properties(xx entity_ref.index);
        {
            using entity_phys_props;
            mass = 1.0;
            body_elasticity = 0.0;
        }

        mesh := get_or_load_mesh("experimental/FinalBaseMesh.obj");
        r_val := random_get_zero_to_one_new().(float32);
        set_entity_meshes(entity_ref, .{data=mesh}, .{data=sphere_mesh_mid_poly,albedo=.{tint=.{r=r_val,b=1-r_val,a=0.3}}});

        get_entity(npc, entity_ref);
        npc.position = .{40,0,2+it.(float)*11.0};
    }
    {
        camera_ref := spawn_entity(.CAMERA, name="first person camera");
        get_entity(*first_person_camera, camera_ref);
    }
    // set experimental global pointers
    {
        free_fly_entity = *camera;
        character_entity = *player_character;
        camera_entity = *camera;
    }
    
}

scratch_think :: () {
    player_half_height := player_character.physics_properties.body_collider.half_height;
    player_center := player_character.position + Vector3.{z=player_half_height};
    end_pt := project_point_onto_plane(player_character.position, ground.position, .{0,0,1});
}


#scope_file // ------------------------------------------------------------------------------------------------ { FILE }
