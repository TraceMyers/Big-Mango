// todo: input mapping

free_fly_linear_speed := 80.0;
free_fly_mouse_look_speed := 0.2;
first_person_mouse_look_speed := 0.2;

jump_queued: bool;
jump_queued_at_time: float;

ortho_scale := 10.0; @command_line

dbg_character_move_input: Vector2;

process_entity_input :: () {
    if control_mode == .FREE_FLY {
        handle_free_fly_input(context.camera_2);
    } else if control_mode == .FIRST_PERSON {
        handle_first_person_input(context.player_entity, context.camera_1);
    } else {
        context.camera_2.projection = .ORTHOGRAPHIC;
        context.camera_2.orthographic.scale = ortho_scale;
        if control_mode == {
        case .ORTHO_YZ_45_DOWN;
            sin_t, cos_t := sin_cos(PI/4);
            set_orientation(context.camera_2, .{0,sin_t,-cos_t}, .{0,cos_t,sin_t});
        case .ORTHO_YZ;
            set_orientation(context.camera_2, .{y=1}, .{z=1});
        case .ORTHO_XZ;
            set_orientation(context.camera_2, .{x=1}, .{z=1});
        case .ORTHO_XY;
            set_orientation(context.camera_2, .{z=-1}, .{y=1});
        }

        handle_ortho_input(context.player_entity, context.camera_2);
        target_camera_pos := context.player_entity.position - fore_direction(context.camera_2) * 100.0;
        if control_mode == prev_control_mode {
            context.camera_2.position = exponential_interp(context.camera_2.position, target_camera_pos, 10.0, delta_time);
        } else {
            context.camera_2.position = target_camera_pos;
        }
    }
}

handle_free_fly_input :: (entity: *Entity) {
    if input_focus != .GAME then return;

    entity.linear_velocity = .{};
    if entity.camera != null {
        entity.camera.projection = .PERSPECTIVE;
        entity.camera.perspective.vertical_fov = 90.0;
        entity.camera.perspective.aspect_ratio = 0.0;
    }

    dt_speed := free_fly_linear_speed * delta_time;

    if Input.input_button_states[#char "W"] & .DOWN {
        entity.position += fore_direction(entity) * dt_speed;
    }
    if Input.input_button_states[#char "S"] & .DOWN {
        entity.position -= fore_direction(entity) * dt_speed;
    }
    if Input.input_button_states[#char "D"] & .DOWN {
        entity.position += right_direction(entity) * dt_speed;
    }
    if Input.input_button_states[#char "A"] & .DOWN {
        entity.position -= right_direction(entity) * dt_speed;
    } 
    if Input.input_button_states[#char "Z"] & .DOWN {
        entity.position += up_direction(entity) * dt_speed;
    }
    if Input.input_button_states[#char "X"] & .DOWN {
        entity.position -= up_direction(entity) * dt_speed;
    }

    if !mouse_look_locked {
        rot_dt_speed := free_fly_mouse_look_speed * delta_time;
        if abs(Input.mouse_delta_x) > 0 {
            angle := -rot_dt_speed * Input.mouse_delta_x.(float);
            rotate(entity, WORLD_UP, angle);
        }
        if abs(Input.mouse_delta_y) > 0 {
            angle := -rot_dt_speed * Input.mouse_delta_y.(float);
            rotate(entity, right_direction_xy(entity), angle);
        }
    }
}

handle_first_person_input :: (entity: *Entity, fp_camera: *Entity) {
    if input_focus != .GAME then return;

    if control_mode != prev_control_mode {
        fp_camera.orientation = entity.orientation;
    }

    fp_camera.camera.projection = .PERSPECTIVE;
    fp_camera.camera.perspective.vertical_fov = 90.0;
    fp_camera.camera.perspective.aspect_ratio = 0.0;
    handle_camera_relative_movement(entity, fp_camera);

    fp_camera.position = entity.position + Vector3.{z=entity.physics_properties.body_collider.half_height * 0.92};

    if mouse_look_locked then return;

    rot_dt_speed := first_person_mouse_look_speed * delta_time;
    if abs(Input.mouse_delta_x) > 0 {
        angle := -rot_dt_speed * Input.mouse_delta_x.(float);
        rotate(fp_camera, WORLD_UP, angle);
    }
    if abs(Input.mouse_delta_y) > 0 {
        vert_angle_delta := -rot_dt_speed * Input.mouse_delta_y.(float);
        cam_forward := fore_direction(fp_camera);
        cam_forward_2d := fore_direction_xy(*fp_camera.orientation);

        // if cos_t < -1 or > 1, then acos(cos_t) is nan.
        // not sure what is going on with normalization s.t. it has noticeable error. maybe that's normal and I'm used to systems that handle it well for me.
        cos_t := clamp(dot(cam_forward, cam_forward_2d), -1, 1);
        t := acos(cos_t);

        VERT_ANGLE_PROPORTION :: 0.9;
        MAX_ANGLE :: PI * 0.5 * VERT_ANGLE_PROPORTION;
        MIN_ANGLE :: -MAX_ANGLE;
        ANGLE_DIFFERENCE :: MAX_ANGLE - MIN_ANGLE;
        angle_remain := max(MAX_ANGLE - t, 0);
        cos_phi := dot(cam_forward, WORLD_UP);
        clamped_delta: float;
        if cos_phi > 0 {
            clamped_delta = clamp(vert_angle_delta, MIN_ANGLE - ANGLE_DIFFERENCE * 0.5 + angle_remain, angle_remain);
        } else {
            clamped_delta = clamp(vert_angle_delta, -angle_remain, MAX_ANGLE + ANGLE_DIFFERENCE * 0.5 - angle_remain);
        }
        cam_right := right_direction_xy(fp_camera);
        rotate(fp_camera, cam_right, clamped_delta);
    }

    xy_2d_forward := fore_direction_xy(*fp_camera.orientation);
    set_orientation(entity, xy_2d_forward, WORLD_UP);

}

handle_ortho_input :: (entity: *Entity, follow_camera: *Entity) {
    if input_focus != .GAME then return;
    handle_camera_relative_movement(entity, follow_camera);
}

handle_camera_relative_movement :: (entity: *Entity, rel_camera: *Entity) {
    target := entity.orientation;
    camera_xy_orientation: Quaternion;
    camera_fore_axis := fore_direction(*rel_camera.orientation);
    cos_t := abs(dot(camera_fore_axis, WORLD_UP));
    camera_up_axis_xy: Vector3;
    if cos_t >= COS_PI_OVER_32 {
        camera_up_axis_xy = up_direction(*rel_camera.orientation);
        camera_up_axis_xy.z = 0;
        normalize(*camera_up_axis_xy);
    } else {
        camera_up_axis_xy = fore_direction_xy(*rel_camera.orientation);
    }
    set_orientation(*camera_xy_orientation, camera_up_axis_xy, .{0,0,1});

    move_dir: Vector2;

    if Input.input_button_states[#char "W"] & .DOWN {
        target = camera_xy_orientation;
        move_dir += fore_direction_xy(*target).xy;
    }
    if Input.input_button_states[#char "S"] & .DOWN {
        target = camera_xy_orientation;
        rotate(*target, .{0,0,1}, PI);
        move_dir += fore_direction_xy(*target).xy;
    }
    if Input.input_button_states[#char "D"] & .DOWN {
        target = camera_xy_orientation;
        rotate(*target, .{0,0,1}, -PI/2);
        move_dir += fore_direction_xy(*target).xy;
    }
    if Input.input_button_states[#char "A"] & .DOWN {
        target = camera_xy_orientation;
        rotate(*target, .{0,0,1}, PI/2);
        move_dir += fore_direction_xy(*target).xy;
    }

    if move_dir == .{0,0} {
        move_dir = dbg_character_move_input;
    }

    if move_dir != .{0,0} {
        move_dir = normalize(move_dir);
        entity.linear_input.xy = move_dir;
        entity.linear_input.z = 0;
    }

    if jump_queued {
        time_since_queued := seconds_since_init().(float) - jump_queued_at_time;
        if time_since_queued < 0.3 {
            entity.physics_flags |= .JUMP_QUEUED;
            entity.jump_queued_at_time = jump_queued_at_time;
        }
        jump_queued_at_time = -999.0;
        jump_queued = false;
    }
}

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// command line procs

input_set_move :: (args: []Command_Line_Argument) {
    init_command_line_proc_or_return(args, 2);
    x, success_x := try_parse_command_line_arg(*args[0], float64);
    y, success_y := try_parse_command_line_arg(*args[1], float64);
    if success_x && success_y {
        dbg_character_move_input = .{xx x, xx y};
    } else {
        rm_error("failed parsing inputs as floats: %, %", args[0]._string, args[1]._string);
    }
} @command_line