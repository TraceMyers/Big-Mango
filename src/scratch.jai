

_scratch :: (stage: Boot_Stage) -> bool {
    if stage == .SHUTDOWN then return true;

    {
        // moving window to top monitor only *after* swapchain creation. something in that process creates a very jittery framerate if the swapchain is created when the window is positioned within that monitor's rect.
        move_window(.{90, -1300});
    }
    // ground entity
    {
        context.ground = spawn_entity("ground", .[]);

        set_shape_and_mass(context.ground, .{type=.RECT, rect=.{200,200}}, IMMOVABLE_ENTITY_MASS);
        set_orientation(context.ground, .{0,0,1}, .{1,0,0});

        context.ground.physics_properties.elasticity = 0.4;
        context.ground.center.z = 0.0;
    }
    // wall entity
    {
        wall := spawn_entity("wall", .[]);
        set_shape_and_mass(wall, .{type=.RECT, rect=.{60, 200}}, IMMOVABLE_ENTITY_MASS);
        set_orientation(wall, .{y=-1}, .{z=1});
        wall.center = .{y=200};
    }
    // camera init
    {
        // temp camera stuff;
        context.camera_1 = spawn_camera("camera 1");
    }
    // fp camera
    {
        context.camera_2 = spawn_camera("camera 2");
        context.camera_2.center.z = 50;
    }
    // character / character mesh
    {
        context.player_entity = spawn_human("player");
        // unset(*context.player_entity.flags, .APPLY_GRAVITY);
        context.player_entity.center.xy = .{0,0};
        context.player_entity.center.z = 2.0;
        context.player_entity.think_proc = player_entity_think;
        context.player_entity.attached_camera = context.camera_1.ref;
    }
    for 0..0
    {
        ai_entity := spawn_entity("ball", .[.DRAW_COLLIDER_HEIGHT_LINE, .PHYSICS_DRIVEN_ROTATION, .APPLY_GRAVITY, .ACCELERATE_IN_3D]);
        set_shape_and_mass(ai_entity, .{type=.SPHERE, sphere=.{3}}, 0.5);

        ai_entity.center.xy = .{0, 10};
        ai_entity.center.z = context.player_entity.center.z + context.player_entity.shape.half_height + ai_entity.shape.sphere.radius * 2.0 * it.(float) + ai_entity.shape.sphere.radius + 0.1 * it.(float);
        context.ball = ai_entity;
        context.ball.physics_properties.elasticity = 1.0;
        context.ball.physics_properties.linear_speed_max = 1000;
    }
    return true;
}

scratch_think :: () {
    color_state: Random_State;
    seeded_height_line_color: bool;

    for e : entities {
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

    if control_mode & FIRST_PERSON_CONTROL_MODE && context.player_entity != null {
        attached_camera := try_get_entity(*context.player_entity.attached_camera);
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