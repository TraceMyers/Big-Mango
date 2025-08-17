// todo: input mapping
// 
free_fly_linear_speed := 80.0;
free_fly_mouse_look_speed := 0.2;
first_person_mouse_look_speed := 0.2;

jump_queued: bool;
jump_queued_at_time: float;

ortho_scale := 10.0; @command_line

dbg_character_move_input: Vector3;

process_entity_input :: (e: *Entity) {
    if input_focus != .GAME then return;
}

process_entity_input :: () {
    using context.world;

    player_entity := try_get_entity(*player_entity_ref);
    camera_1 := try_get_entity(*camera_1_ref);
    camera_2 := try_get_entity(*camera_2_ref);

    if player_entity == null then return;
    if input_focus != .GAME then return;

    if control_mode == .FIRST_PERSON_CAMERA_ONLY {
        if camera_2 != null {
            set(*camera_2.flags, .ACCELERATE_IN_3D);
            handle_first_person_input(camera_2, null, .{}, true);
        }
    } else if control_mode == .FIRST_PERSON_PLAYER {
        attached_camera := get_entity(player_entity.attached_camera);
        if player_entity != null && attached_camera != null {
            unset(*player_entity.flags, .ACCELERATE_IN_3D);
            first_person_camera_offset := Vector3.{z=player_entity.body.shape.half_height * 0.92};
            handle_first_person_input(player_entity, attached_camera, first_person_camera_offset, false);
            handle_player_input(player_entity);
        }
    } else if control_mode == .FIRST_PERSON_PLAYER_FREE_FLY {
        if player_entity != null && camera_1 != null {
            set(*player_entity.flags, .ACCELERATE_IN_3D);
            first_person_camera_offset := Vector3.{z=player_entity.body.shape.half_height * 0.92};
            handle_first_person_input(player_entity, camera_1, first_person_camera_offset, true);
            handle_player_input(player_entity);
        }
    } else { // ortho
        if player_entity != null && camera_2 != null {
            unset(*player_entity.flags, .ACCELERATE_IN_3D);
            handle_ortho_input(player_entity, camera_2);
            handle_player_input(player_entity);
        }
    }

    if player_entity != null {
        apply_acceleration(player_entity);
    }
}

handle_first_person_input :: (entity: *Entity, fp_camera: *Entity, camera_offset: Vector3, free_fly: bool) {
    if fp_camera == null then fp_camera = entity;

    if control_mode != prev_control_mode {
        fp_camera.orientation = entity.orientation;
    }

    fp_camera.camera.projection = .PERSPECTIVE;
    fp_camera.camera.perspective.vertical_fov = 90.0;
    fp_camera.camera.perspective.aspect_ratio = 0.0;
    handle_camera_relative_movement(entity, fp_camera, free_fly);

    if fp_camera != entity {
        fp_camera.center = entity.center + camera_offset;
    }

    if !cursor_locked_to_center then return;

    rot_dt_speed := first_person_mouse_look_speed * delta_time;
    if abs(Input.mouse_delta_x) > 0 {
        angle := -rot_dt_speed * Input.mouse_delta_x.(float);
        rotate(fp_camera, WORLD_UP, angle);
    }
    if abs(Input.mouse_delta_y) > 0 {
        vert_angle_delta := -rot_dt_speed * Input.mouse_delta_y.(float);
        cam_forward := fp_camera.axes.fore;
        cam_forward_2d := Vector3.{xy=fore_direction_xy(fp_camera)};

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
        cam_right := Vector3.{xy=right_direction_xy(fp_camera)};
        rotate(fp_camera, cam_right, clamped_delta);
    }

    if fp_camera != entity {
        xy_2d_forward := fore_direction_xy(*fp_camera.orientation);
        set_orientation(entity, xy_2d_forward, WORLD_UP);
    }
}

handle_ortho_input :: (entity: *Entity, follow_camera: *Entity) {
    follow_camera.projection = .ORTHOGRAPHIC;
    follow_camera.orthographic.scale = ortho_scale;

    if control_mode == {
    case .ORTHO_YZ_45_DOWN;
        sin_t, cos_t := sin_cos(PI/4);
        set_orientation(follow_camera, .{0,sin_t,-cos_t}, .{0,cos_t,sin_t});
    case .ORTHO_YZ;
        set_orientation(follow_camera, .{y=1}, .{z=1});
    case .ORTHO_XZ;
        set_orientation(follow_camera, .{x=1}, .{z=1});
    case .ORTHO_XY;
        set_orientation(follow_camera, .{z=-1}, .{y=1});
    }

    handle_camera_relative_movement(entity, follow_camera, false);

    target_camera_pos := entity.center - follow_camera.axes.fore * 100.0;
    if control_mode == prev_control_mode {
        follow_camera.center = exponential_interp(follow_camera.center, target_camera_pos, 10.0, delta_time);
    } else {
        follow_camera.center = target_camera_pos;
    }
}

handle_camera_relative_movement :: (entity: *Entity, rel_camera: *Entity, move_in_3d: bool) {
    if rel_camera == null then rel_camera = entity;

    target := entity.orientation;

    camera_orientation: Quaternion;
    if move_in_3d {
        camera_orientation = *rel_camera.orientation;
    } else {
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
        set_orientation(*camera_orientation, camera_up_axis_xy, .{0,0,1});
    }

    axis_fore, axis_up, axis_right: Vector3;
    get_axes(camera_orientation, *axis_fore, *axis_up, *axis_right);

    move_dir: Vector3;

    if window_is_active() && (Input.input_button_states[Input.Key_Code.CTRL] & .DOWN) == 0 {
        if Input.input_button_states[#char "W"] & .DOWN {
            move_dir += axis_fore;
        }
        if Input.input_button_states[#char "S"] & .DOWN {
            move_dir -= axis_fore;
        }
        if Input.input_button_states[#char "D"] & .DOWN {
            move_dir += axis_right;
        }
        if Input.input_button_states[#char "A"] & .DOWN {
            move_dir -= axis_right;
        }
    }

    // paranoid/safe
    if !move_in_3d {
        move_dir.z = 0;
    } else if move_dir != .{0,0,0} {
        a := 0;
    }

    if move_dir == .{0,0,0} {
        move_dir = dbg_character_move_input;
    }

    if move_dir != .{0,0,0} {
        move_dir = normalize(move_dir);
        entity.linear_input = move_dir;
    }
}

handle_player_input :: (entity: *Entity) {
    if Input.input_button_states[#char "E"] & .DOWN {
        
    }
}

    // if jump_queued {
    //     time_since_queued := seconds_since_init().(float) - jump_queued_at_time;
    //     if time_since_queued < 0.3 {
    //         entity.movement_flags |= .JUMP_QUEUED;
    //         entity.jump_queued_at_time = jump_queued_at_time;
    //     }
    //     jump_queued_at_time = -999.0;
    //     jump_queued = false;
    // }

// /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// command line procs

input_set_move :: (args: []Command_Line_Argument) {
    init_command_line_proc_or_return(args, 1, 3);
    arg0 := args[0];
    arg1 := ifx args.count >= 2 then args[1] else Command_Line_Argument.{};
    arg2 := ifx args.count == 3 then args[2] else Command_Line_Argument.{};
    x, success_x := try_parse_command_line_arg(*arg0, float64);
    y, success_y := try_parse_command_line_arg(*arg1, float64);
    z, success_z := try_parse_command_line_arg(*arg2, float64);
    if success_x && success_y && success_z {
        dbg_character_move_input = .{xx x, xx y, xx z};
    } else if success_x && success_y {
        dbg_character_move_input = .{xx x, xx y,    0};
    } else if success_x {
        dbg_character_move_input = .{xx x,    0,    0};
    } else {
        rm_error("failed parsing inputs as floats: %, %, %", arg0._string, arg1._string, arg2._string);
    }
} @command_line

teleport_player_to_free_fly_camera :: (args: []Command_Line_Argument) {
    init_command_line_proc_or_return(args, 0);
    get_entity(context.world.player_entity_ref).center = get_entity(context.world.camera_2_ref).center;
} @command_line