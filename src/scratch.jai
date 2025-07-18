

scratch_init_game :: () {
    {
        // moving window to top monitor only *after* swapchain creation. something in that process creates a very jittery framerate if the swapchain is created when the window is positioned within that monitor's rect.
        move_window(.{90, -1300});
    }
    {
        fixed_delta_time = 1.0/80.0;
        // fixed_delta_time = 1.0 / 60.0;
        // fixed_delta_time = 1.0 / 1000.0;
    }
    // ground entity
    {
        entity_ref := spawn_entity(.STATIC_MESH, name="ground", physics_properties_template=.GROUND, make_physics_properties_dynamic=true);

        phys_props := get_entity_physics_properties(entity_ref);
        {
            using phys_props;
            body_collider.type = .PLANE;
            body_collider.plane.half_height = 500.0;
            body_collider.plane.half_width = 500.0;
            body_elasticity = 0.01;
            gravity_accel = 0.0;
            mass = IMMOVABLE_ENTITY_MASS;
        }

        set_entity_meshes(entity_ref, .{plane_mesh,.{}});

        ground: Entity;
        get_entity(*ground, entity_ref);
        set_orientation(*ground.orientation, .{0,0,1}, .{1,0,0});
        // rotate(*ground, WORLD_RIGHT, 0.5);
        ground.position.z = 0.0;
    }
    // camera init
    {
        // temp camera stuff;
        context.camera_1.ref = spawn_entity(.CAMERA, name="camera 1", physics_properties_template=.CAMERA);
        get_entity(*context.camera_1, context.camera_1.ref);
    }
    // fp camera
    {
        context.camera_2.ref = spawn_entity(.CAMERA, name="camera 2", physics_properties_template=.CAMERA);
        get_entity(*context.camera_2, context.camera_2.ref);
    }
    // npc 
    // for 0..0
    // {
    //     entity_ref := spawn_entity_human(name="npc", physics_properties_template=.SPHERE_MAN, make_physics_properties_dynamic=true);

    //     entity_phys_props := get_entity_physics_properties(entity_ref);
    //     {
    //         using entity_phys_props;
    //         mass = 1.0;
    //         body_elasticity = 0.0;
    //     }

    //     reorient_mesh_quat: Quaternion;
    //     set_orientation(*reorient_mesh_quat, .{0,0,1}, .{0,1,0});
    //     mesh := get_or_load_mesh("experimental/FinalBaseMesh.obj", true, reorient_mesh_quat, .{0,0,-5.0});

    //     r_val := random_get_zero_to_one_new().(float32);
    //     set_entity_meshes(entity_ref, .{data=mesh}, .{data=sphere_mesh_mid_poly,albedo=.{tint=.{r=r_val,b=1-r_val,a=0.3}}});

    //     npc: Entity;
    //     get_entity(*npc, entity_ref);
    //     y := it / 10;
    //     x := it - y * 10;
    //     SCALE :: 20.0;
    //     npc.position = .{x * SCALE,y * SCALE,2};
    //     array_add(*test_entities, entity_ref);
    // }
    // character / character mesh
    {
        context.player_entity.ref = spawn_entity_human(name="player", physics_properties_template=.SPHERE_MAN, make_physics_properties_dynamic=true);

        entity_phys_props := get_entity_physics_properties(context.player_entity.ref);
        {
            using entity_phys_props;
            mass = 1.0;
            body_elasticity = 0.0;
        }

        // array_add(*physics_debugger_entity_ids, context.player_entity.ref.id);

        reorient_mesh_quat: Quaternion;
        set_orientation(*reorient_mesh_quat, .{0,0,1}, .{0,1,0});

        mesh := get_or_load_mesh("experimental/FinalBaseMesh.obj", true, reorient_mesh_quat, .{0,0,-5.0});
        set_entity_meshes(context.player_entity.ref, .{mesh, .{tint=.{0.7,0.7,0.9,1.0}}}, .{sphere_mesh_mid_poly, .{tint=.{0.6, 0.1, 0.9, 0.5}}});

        get_entity(*context.player_entity, context.player_entity.ref);
        context.player_entity.position.xy = .{40,40};
        context.player_entity.position.z = 50.0;
    }
}

scratch_think :: () {
    player_half_height := context.player_entity.physics_properties.body_collider.half_height;
    player_center := context.player_entity.position + Vector3.{z=player_half_height};
    end_pt := project_point_onto_plane(context.player_entity.position, .{}, .{0,0,1});

    // rotate(*ground, WORLD_UP, delta_time*0.25);
}


#scope_file // ------------------------------------------------------------------------------------------------ { FILE }
