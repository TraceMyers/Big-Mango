
FIXED_TIME_STEP :: 1.0 / 60.0;

// the collision resolution is going to be complicated, so for now I just want very simple movement to debug collisions.
move_stuff :: () {
    scope_timer();
    entity_ct := get_entity_count();
    for 0..entity_ct-1 {
        movement := get_movement_at(it);
        body := get_body_at(it);
        props := get_physics_properties_at(it);
        body.previous_center = body.center;

        // friction (in future just handle in the physics solving)
        if movement.movement_flags & .ACCELERATE_IN_3D {
            apply_friction(*body.velocity, props);
            if movement.linear_input != .{} {
                apply_acceleration(*body.velocity, movement.linear_input, props);
            }
        } else {
            apply_friction(*body.velocity.xy, props);
            if movement.linear_input != .{} {
                apply_acceleration(*body.velocity.xy, movement.linear_input.xy, props);
            }
        }
        movement.linear_input = .{};

        body.center += body.velocity * FIXED_TIME_STEP;
    }
}

apply_acceleration :: (velocity: *$T/VectorTypes, linear_input: T, props: *Physics_Properties) {
    prev_speed_sq := length_squared(velocity.*);
    linear_accel := props.linear_acceleration;

    if prev_speed_sq > VERY_SMALL_NUMBER {
        prev_speed := sqrt(prev_speed_sq);
        prev_velocity_dir := velocity.* / prev_speed;
        cos_t := dot(linear_input, prev_velocity_dir);
        if cos_t <= COS_PI_OVER_4 {
            linear_accel *= props.accel_opposite_direction_multiplier;
        }
    }
    if prev_speed_sq <= props.fast_start_speed_max {
        linear_accel *= props.fast_start_speed_multiplier;
    }

    velocity.* += linear_input * (linear_accel * FIXED_TIME_STEP);
    new_speed_sq := length_squared(velocity);

    if new_speed_sq > square(props.linear_speed_max) {
        new_speed := sqrt(new_speed_sq);
        velocity.* *= props.linear_speed_max / new_speed;
    }
}

apply_friction :: (velocity: *$T/VectorTypes, props: *Physics_Properties) {
    linear_speed_sq := length_squared(velocity.*);
    if linear_speed_sq > VERY_SMALL_NUMBER {
        linear_speed := sqrt(linear_speed_sq);
        velocity_direction := velocity.* / linear_speed;

        // todo: material friction, static friction
        ground_friction := 0.8;
        friction_coef := max(ground_friction * props.friction_multiplier + props.friction_bias, 0);
        friction_accel := friction_coef * 98.0;
        friction_delta := friction_accel * FIXED_TIME_STEP;

        if friction_delta > linear_speed {
            velocity.* = .{};
        } else {
            velocity.* -= velocity_direction * friction_delta;
        }
    } else {
        velocity.* = .{};
    }
} 