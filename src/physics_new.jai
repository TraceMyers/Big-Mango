
move_stuff :: (time_step: float) {
    scope_timer();

    for 0..context.world.entities.count-1 {
        e := *context.world.entities[it];
        e.previous_center = e.center;

        // friction (in future just handle in the physics solving)
        if is_set(*e.flags, .ACCELERATE_IN_3D) {
            // apply_friction(*e.velocity, e.physics_properties.friction_multiplier, e.physics_properties.friction_bias, time_step);
        } else {
            apply_friction(*e.velocity.xy, e.physics_properties.friction_multiplier, e.physics_properties.friction_bias, time_step);
        }

        e.center += e.velocity * time_step;

        MAX_ANGULAR_SPEED :: 1.0;
        angular_speed_sq := length_squared(e.angular_velocity);
        if angular_speed_sq > MAX_ANGULAR_SPEED {
            angular_speed := sqrt(angular_speed_sq);
            e.angular_velocity *= MAX_ANGULAR_SPEED / angular_speed;
        }

        rotation_axis_scaled := e.angular_velocity * time_step;
        rotation_axis_scalar_len_sq := length_squared(rotation_axis_scaled);
        if rotation_axis_scalar_len_sq > VERY_SMALL_NUMBER {
            rotation_magnitude := sqrt(rotation_axis_scalar_len_sq);
            rotation_axis := rotation_axis_scaled / rotation_magnitude;
            rotate(e, rotation_axis, rotation_magnitude);
        }

        if !is_set(*e.flags, .ACCELERATE_IN_3D) {
            new_speed_sq := length_squared(e.velocity.xy);
            if new_speed_sq > square(e.physics_properties.linear_speed_max) {
                new_speed := sqrt(new_speed_sq);
                e.velocity.xy *= e.physics_properties.linear_speed_max / new_speed;
            }
            if abs(e.velocity.z) > e.physics_properties.fall_speed_max {
                e.velocity.z = e.physics_properties.fall_speed_max * sign(e.velocity.z);
            }
        }

        if e.center.z <= Z_KILL_FLOOR {
            queue_entity_deletion(e.ref);
        }

        VELOCITY_REGULATION_DAMPEN_PER_SECOND :: 0.1; 
        degrade_over_time(*e.velocity, VELOCITY_REGULATION_DAMPEN_PER_SECOND, time_step);
        degrade_over_time(*e.angular_velocity, VELOCITY_REGULATION_DAMPEN_PER_SECOND, time_step);
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
        add_linear_impulse(e, .{force, 1./100});
    }
    e.linear_input = .{};
}

apply_friction :: (velocity: *$T/VectorTypes, friction_multiplier: float, friction_bias: float, time_step: float) {
    linear_speed_sq := length_squared(velocity.*);
    if linear_speed_sq > VERY_SMALL_NUMBER {
        linear_speed := sqrt(linear_speed_sq);
        velocity_direction := velocity.* / linear_speed;

        // todo: material friction, static friction
        ground_friction := 0.4;
        friction_coef := max(ground_friction * friction_multiplier + friction_bias, 0);
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

