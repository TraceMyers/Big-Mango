// todo: input mapping

free_fly_entity: *Entity;

character_entity: *Entity;
camera_entity: *Entity;

free_fly_linear_speed := 200.0;
free_fly_mouse_look_speed := 0.2;

process_entity_input :: () {
    if control_mode == .FREE_FLY {
        handle_free_fly_input(free_fly_entity);
    } else if control_mode == .CHARACTER {
        handle_character_input(character_entity, camera_entity);
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

handle_character_input :: (entity: *Entity, follow_camera: *Entity) {
    if follow_camera != null {
        follow_camera.projection = .ORTHOGRAPHIC;
        cos_t := cos(PI/4);
        sin_t := sin(PI/4);
        set_orientation(follow_camera, .{0,sin_t,-cos_t}, .{0,cos_t,sin_t});
        follow_camera.orthographic.scale = 10;
    }

    if input_focus != .GAME then return;

    target := entity.orientation;
    camera_xy_orientation: Quaternion;
    set_orientation(*camera_xy_orientation, fore_direction_xy(*follow_camera.orientation), .{0,0,1});

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

    if move_dir != .{0,0} {
        move_dir = normalize(move_dir);
        prev_speed_sq := length_squared(entity.linear_velocity.xy);
        linear_accel := entity.physics_properties.linear_acceleration;

        if prev_speed_sq > 0.0001 {
            prev_speed := sqrt(prev_speed_sq);
            prev_velocity_dir := entity.linear_velocity.xy / prev_speed;
            cos_t := dot(move_dir, prev_velocity_dir);
            if cos_t <= COS_PI_OVER_4 {
                linear_accel *= entity.physics_properties.accel_opposite_direction_multiplier;
            }
        }
        if prev_speed_sq <= entity.physics_properties.fast_start_speed_max {
            linear_accel *= 4.0;
        }

        entity.linear_velocity.xy += move_dir * (linear_accel * delta_time);
        new_speed_sq := length_squared(entity.linear_velocity.xy);

        if new_speed_sq > square(entity.physics_properties.linear_speed_max) {
            new_speed := sqrt(new_speed_sq);
            entity.linear_velocity.xy *= entity.physics_properties.linear_speed_max / new_speed;
        }

        target = make_quat(.{xy=move_dir, z=0}, WORLD_UP);
        rot_speed := 6.5 * PI;
        interp_rotate(entity, target, rot_speed, delta_time);
    }

    if follow_camera != null {
        target_camera_pos: Vector3 = ---;
        target_camera_pos.xy = entity.position.xy;
        target_camera_pos.xy -= fore_direction(follow_camera).xy * 30.0;
        target_camera_pos.z = entity.position.z + 60.0;
        camera.position = exponential_interp(follow_camera.position, target_camera_pos, 4.0, delta_time);
    }
}