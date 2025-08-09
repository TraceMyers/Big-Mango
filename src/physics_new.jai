
move_stuff :: (time_step: float) {
    scope_timer();
    entity_ct := get_entity_count();
    for 0..entity_ct-1 {
        movement := get_movement_at(it);
        body := get_body_at(it);
        props := get_physics_properties_at(it);
        body.previous_center = body.center;

        // friction (in future just handle in the physics solving)
        if lfa_is_set(*entity_flags[it], .ACCELERATE_IN_3D) {
            apply_friction(*body.velocity, props, time_step);
        } else {
            apply_friction(*body.velocity.xy, props, time_step);
        }

        body.center += body.velocity * time_step;

        MAX_ANGULAR_SPEED :: 1.0;
        angular_speed_sq := length_squared(body.angular_velocity);
        if angular_speed_sq > MAX_ANGULAR_SPEED {
            angular_speed := sqrt(angular_speed_sq);
            body.angular_velocity *= MAX_ANGULAR_SPEED / angular_speed;
        }

        rotation_axis_scaled := body.angular_velocity * time_step;
        rotation_axis_scalar_len_sq := length_squared(rotation_axis_scaled);
        if rotation_axis_scalar_len_sq > VERY_SMALL_NUMBER {
            rotation_magnitude := sqrt(rotation_axis_scalar_len_sq);
            rotation_axis := rotation_axis_scaled / rotation_magnitude;
            rotate(*body.orientation, rotation_axis, rotation_magnitude);
        }

        if !lfa_is_set(*entity_flags[it], .ACCELERATE_IN_3D) {
            new_speed_sq := length_squared(body.velocity.xy);
            if new_speed_sq > square(props.linear_speed_max) {
                new_speed := sqrt(new_speed_sq);
                body.velocity.xy *= props.linear_speed_max / new_speed;
            }
            if abs(body.velocity.z) > props.fall_speed_max {
                body.velocity.z = props.fall_speed_max * sign(body.velocity.z);
            }
        }

        // if body.center.z <= Z_KILL_FLOOR {
        //     queue_entity_deletion(entity_ref(it));
        // }

        VELOCITY_REGULATION_DAMPEN_PER_SECOND :: 0.2; 
        degrade_over_time(*body.velocity, VELOCITY_REGULATION_DAMPEN_PER_SECOND, time_step);
        degrade_over_time(*body.angular_velocity, VELOCITY_REGULATION_DAMPEN_PER_SECOND, time_step);
    }
}

apply_acceleration :: (e: *Entity) {
    prev_speed_sq := length_squared(e.velocity);
    linear_accel := e.physics_properties.linear_acceleration;

    if prev_speed_sq > VERY_SMALL_NUMBER {
        prev_speed := sqrt(prev_speed_sq);
        prev_velocity_dir := e.velocity / prev_speed;
        cos_t := dot(e.linear_input, prev_velocity_dir);
        if cos_t <= COS_PI_OVER_4 {
            linear_accel *= e.physics_properties.accel_opposite_direction_multiplier;
        }
    }
    if prev_speed_sq <= e.physics_properties.fast_start_speed_max {
        linear_accel *= e.physics_properties.fast_start_speed_multiplier;
    }

    force := e.linear_input * (linear_accel * e.physics_properties.mass);
    if length_squared(force) > VERY_SMALL_NUMBER {
        add_linear_impulse(e, force, 1./200);
    }
    e.linear_input = .{};
}

apply_friction :: (velocity: *$T/VectorTypes, props: *Physics_Properties, time_step: float) {
    linear_speed_sq := length_squared(velocity.*);
    if linear_speed_sq > VERY_SMALL_NUMBER {
        linear_speed := sqrt(linear_speed_sq);
        velocity_direction := velocity.* / linear_speed;

        // todo: material friction, static friction
        ground_friction := 0.4;
        friction_coef := max(ground_friction * props.friction_multiplier + props.friction_bias, 0);
        friction_accel := friction_coef * 150.0; // todo: use gravity accel? but what about cameras?
        friction_delta := friction_accel * time_step;

        if friction_delta > linear_speed {
            velocity.* = .{};
        } else {
            velocity.* -= velocity_direction * friction_delta;
        }
    } else {
        velocity.* = .{};
    }
}

