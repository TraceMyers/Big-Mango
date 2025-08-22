

_scratch :: (stage: Boot_Stage) -> bool {
    if stage == .SHUTDOWN then return true; // scratch boot runs in a scope, so it is currently called twice in a row
    using context.world;

    {
        // moving window to top monitor only *after* swapchain creation. something in that process creates a very jittery framerate if the swapchain is created when the window is positioned within that monitor's rect.
        move_window(.{90, -1300});
    }
    // ground entity
    {
        ground := spawn_floor(.{}, .{g=0.8,b=0.7}, 400);
        // ground := spawn_entity("ground", .[]);
        // ground_ref = ground.ref;

        // set_shape_and_mass(ground, .{type=.RECT, rect=.{200, 200, false}}, IMMOVABLE_ENTITY_MASS);
        // set_orientation(ground, .{0,0,1}, .{1,0,0});
        ground.physics_properties.elasticity = 0.4;
    }
    // wall entity
    {
        wall := spawn_wall(.{y=200}, .{g=0.8,b=0.7}, 300);
    }
    another_door: *Entity;
    // door 2, the sequel
    {
        another_door = spawn_swinging_door(.{y=100, x=60}, .{x=1}, .{b=1});
    }
    // door entity
    {
        door := spawn_swinging_door(.{y=100}, .{y=-1}, .{r=1}, 80, 80 * (3./5));
        door_ref = door.ref;
        add_gadget_child(door, .{another_door.ref});
        set(*door.flags, .GADGET_FORCE_INTERACTIONS_AS_PARENT);
        door.door.rotation_speed = PI / 16;
    }
    // camera init
    {
        // temp camera stuff;
        camera_1 := spawn_camera("camera 1");
        camera_1_ref = camera_1.ref;
    }
    // fp camera
    {
        camera_2 := spawn_camera("camera 2");
        camera_2.center.z = 50;
        camera_2_ref = camera_2.ref;
    }
    // character / character mesh
    player_entity: *Entity; 
    {
        player_entity = spawn_human("player");
        player_entity.center.xy = .{0,0};
        player_entity.center.z = 2.0;
        player_entity.attached_camera = camera_1_ref;
        player_entity.ray_channels = 0;
        player_entity_ref = player_entity.ref;
        player_entity.physics_properties.air_friction_multiplier = 4;
        set(*player_entity.flags, .PLAYER_ENTITY_THINK);
        set(*player_entity.flags, .APPLY_AIR_FRICTION);
    }
    // ball
    {
        radius := 3.0;
        ball_init_z := player_entity.center.z + player_entity.shape.half_height + radius;
        ball := spawn_ball(.{y=10,z=ball_init_z} , .{r=0.7,g=0.5}, radius);
        ball_ref = ball.ref;
    }
    // button
    {
        button := spawn_gadget(
            "button", 
            .{
                gadget_type=.BUTTON, 
                button=.{}
            }, 
            .{y=30, z=10}
        );

        radius := 0.5;
        half_height := 0.8;

        set_shape_and_mass(button, .{type=.CAPSULE, capsule=.{half_height, radius}}, IMMOVABLE_ENTITY_MASS);
        button.collision_mesh_albedo.tint = .{g=0.8};
        capsule_mesh := get_or_create_capsule_mesh(half_height*2, radius);
        cube := get_or_load_mesh(*MESH_CUBE);
        set_meshes(button, .[
            .{data=cube, albedo=.{tint=.{r=1,g=1,b=1}}, scale=.{1.5,1.5,2.0}, offset=.{z=-0.7}},
            .{data=capsule_mesh, albedo=.{tint=.{r=1}}}
        ]);
        add_gadget_child(button, .{door_ref});
        set(*button.flags, .GADGET_FORCE_INTERACTIONS_AS_PARENT);
        set(*button.flags, .NEVER_SHOW_COLLIDER_MESH);
        button_ref = button.ref;
    }
    {
        add_gadget_child(another_door, .{button_ref});
        set(*another_door.flags, .GADGET_FORCE_INTERACTIONS_AS_PARENT);
    }
    // ai guy
    {
        // context.ai_guy = spawn_human("derek");
        // context.ai_guy.center.xy = context.door.center.xy * 1.1;
        // context.ai_guy.center.z = context.ai_guy.shape.sphere.radius;
        // context.ai_guy.shape.type = .NONE;
        // context.ai_guy.collision_channels = 0;
        // set_orientation(context.ai_guy, .{y=-1}, .{z=1});
        // unset(*context.ai_guy.flags, .APPLY_GRAVITY);
        // context.ai_guy.gadget_type = .DOOR;
        // context.ai_guy.door.pivot_local_offset = .{x=-15};
        // context.ai_guy.door.closed_orientation = context.ai_guy.orientation;
        // context.ai_guy.door.rotation_angle = 2. * PI;
        // context.ai_guy.door.auto_reset_to_closed = true;
    }

    // temp
    // context.world.world_name = "world";
    // context.world.world_id = 41;
    // load(context.world, "worlds/world_41.world");

    return true;
}

scratch_think :: () {
    color_state: Random_State;
    seeded_height_line_color: bool;

    player_entity := try_get_entity(*context.world.player_entity_ref);

    for e : context.world.entities {
        if is_set(*e.flags, .DRAW_COLLIDER_HEIGHT_LINE) {
            if !seeded_height_line_color {
                random_seed(*color_state, 512);
                seeded_height_line_color = true;
            }
            color := random_color4f(random_state=*color_state);
            draw_line(e.center, e.center + e.axes.up * e.shape.half_height, color, color, 0.0, start_point_radius=0.3, end_point_radius=0.3);
            draw_line(e.center, e.center - e.axes.up * e.shape.half_height, .{r=1,g=1,b=1});
        }
    }

    if control_mode & FIRST_PERSON_CONTROL_MODE && player_entity != null {
        attached_camera := try_get_entity(*player_entity.attached_camera);
        if attached_camera != null {
            pos_in_front := attached_camera.center + attached_camera.axes.fore;
            draw_crosshair_line(pos_in_front, 0.1, 0.05, -attached_camera.axes.right);
            draw_crosshair_line(pos_in_front, 0.1, 0.05, attached_camera.axes.right);
            draw_crosshair_line(pos_in_front, 0.1, 0.05, -attached_camera.axes.up);
            draw_crosshair_line(pos_in_front, 0.1, 0.05, attached_camera.axes.up);
        }
    }

    // spawn_timer -= delta_time;
    // if spawn_timer < 0 {
    //     ai_entity := spawn_human("ai guy", center = .{z=10});
    //     set(*ai_entity.flags, .DRAW_COLLIDER_HEIGHT_LINE);
    //     spawn_timer = 0.3;
    // }
    // rotate(*ground, WORLD_UP, delta_time*0.25);
}


#scope_file // ------------------------------------------------------------------------------------------------ { FILE }

spawn_timer: float;