

_scratch :: (stage: Boot_Stage) -> bool {
    if stage == .SHUTDOWN then return true;

    {
        // moving window to top monitor only *after* swapchain creation. something in that process creates a very jittery framerate if the swapchain is created when the window is positioned within that monitor's rect.
        move_window(.{90, -1300});
    }
    // ground entity
    {
        context.ground = spawn_entity(.STATIC_ENVIRONMENT, name="ground", physics_properties_template=.GROUND, make_physics_properties_dynamic=true);

        context.ground.body.shape.type = .RECT;
        context.ground.body.shape.rect.half_height = 50.0;
        context.ground.body.shape.rect.half_width = 50.0;

        phys_props := get_entity_physics_properties(context.ground.ref);
        {
            using phys_props;

            body_elasticity = 0.01;
            gravity_accel = 0.0;
            mass = IMMOVABLE_ENTITY_MASS;
        }

        set_entity_meshes(context.ground.ref, .{plane_mesh,.{}});

        set_orientation(*context.ground.orientation, .{0,0,1}, .{1,0,0});
        // rotate(*ground, WORLD_RIGHT, 0.5);
        context.ground.center.z = 0.0;
    }
    // camera init
    {
        // temp camera stuff;
        context.camera_1 = spawn_entity(.CAMERA, name="camera 1", physics_properties_template=.CAMERA);
    }
    // fp camera
    {
        context.camera_2 = spawn_entity(.CAMERA, name="camera 2", physics_properties_template=.CAMERA);
        context.camera_2.center.z = 50;
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
        context.player_entity = spawn_entity_human(name="player", physics_properties_template=.SPHERE_MAN, make_physics_properties_dynamic=true);

        // context.player_entity.collision_channels.* = 0;

        // context.player_entity.ai.update = scratch_ai_update;
        // context.player_entity.movement_flags |= .CONTROL_ATTACHED_CAMERA;
        // context.player_entity.movement_flags |= .MOVE_RELATIVE_TO_CAMERA;
        // context.player_entity.attached_camera = context.camera_1.ref;
        // context.player_entity.ai.input_oscillation_max_time = 5;
        // context.player_entity.ai.input_direction = .DOWN;

        set_body_shape_and_mass(context.player_entity.ref, .{type=.SPHERE, sphere=.{radius=10}}, 1);

        // array_add(*physics_debugger_entity_ids, context.player_entity.ref.id);

        reorient_mesh_quat: Quaternion;
        set_orientation(*reorient_mesh_quat, .{0,0,1}, .{0,1,0});

        lfa_set(context.player_entity.flags, .APPLY_GRAVITY);
        // lfa_unset(context.player_entity.flags, .MOVED_BY_PHYSICS);

        mesh := get_or_load_mesh("experimental/FinalBaseMesh.obj", true, reorient_mesh_quat, .{0,0,-5.0});
        set_entity_meshes(context.player_entity.ref, .{mesh, .{tint=.{0.7,0.7,0.9,1.0}}});

        context.player_entity.center.xy = .{0,0};
        context.player_entity.center.z = 5.0;
    }
    for 0..20
    {
        ai_entity := spawn_entity_human(name="ai guy", physics_properties_template=.SPHERE_MAN, make_physics_properties_dynamic=true);
        ai_entity.ai.input_oscillation_max_time = 5;
        ai_entity.ai.input_oscillation_timer = random_get_within_range(0, 5);
        val := it & 0x3;
        if val == 3 then val = 0;
        if val == {
        case 0;
            ai_entity.ai.input_direction = ifx it & 1 == 0 then .LEFT else .RIGHT;
        case 1; 
            ai_entity.ai.input_direction = ifx it & 1 == 0 then .FORE else .BACK;
        case 2;
            ai_entity.ai.input_direction = ifx it & 1 == 0 then .UP else .DOWN;
        }

        radius := 10.0;
        set_body_shape_and_mass(ai_entity.ref, .{type=.SPHERE, sphere=.{radius=radius}}, 1);

        lfa_set(ai_entity.flags, .DRAW_COLLIDER_HEIGHT_LINE);
        lfa_set(ai_entity.flags, .PHYSICS_DRIVEN_ROTATION);
        lfa_set(ai_entity.flags, .APPLY_GRAVITY);

        // set_entity_meshes(ai_entity.ref, .{sphere_mesh_mid_poly, .{tint=.{0.6, 0.1, 0.9, 0.2}}});
        ai_entity.center.xy = .{};
        // ai_entity.center.z = 5.0;
        ai_entity.center.z = context.player_entity.center.z + context.player_entity.shape.half_height + ai_entity.shape.sphere.radius * 2.0 * it.(float) + ai_entity.shape.sphere.radius + 0.1 * it.(float);
    }
    return true;
}

scratch_think :: () {
    entity_ct := get_entity_count();

    color_state: Random_State;
    seeded_height_line_color: bool;

    for 0..entity_ct-1 {
        body := get_body_at(it);
        if lfa_is_set(*entity_flags[it], .DRAW_COLLIDER_HEIGHT_LINE) {
            if !seeded_height_line_color {
                random_seed(*color_state, 512);
                seeded_height_line_color = true;
            }
            draw_line_with_points(body.center, body.center + up_direction_at(it) * body.shape.half_height, random_color4f(random_state=*color_state));
            draw_line(body.center, body.center - up_direction_at(it) * body.shape.half_height, .{r=1,g=1,b=1});
        }
    }

    // rotate(*ground, WORLD_UP, delta_time*0.25);
}


#scope_file // ------------------------------------------------------------------------------------------------ { FILE }
