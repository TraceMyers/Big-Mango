
update_thinks :: () {
    for *e : entities {
        if is_set(*e.flags, .PLAYER_ENTITY_THINK) {
            player_entity_think(e);
        }
        if is_set(*e.flags, .DOOR_THINK) {
            door_think(e);
        }
    }
}

player_entity_think :: (e: *Entity) {
    holding_entity := try_get_entity(*e.holding_entity);
    if is_set(*e.flags, .USE_INTERACTION_QUEUED) {
        if holding_entity != null {
            set(*holding_entity.flags, .MOVED_BY_PHYSICS);
            set(*holding_entity.flags, .APPLY_GRAVITY);
            holding_entity.collision_channels = .DEFAULT;
            holding_entity.velocity = e.velocity;
            add_linear_impulse(holding_entity, .{look_direction(e) * 10_000.0 * holding_entity.physics_properties.mass, 1./100.0});
            e.holding_entity = .{};
        } else {
            result: Raycast_Result;
            request: Raycast_Request;
            request.ray = .{look_origin(e), look_direction(e)};
            request.channels = .DEFAULT_1;
            if raycast(*request, *result) && !is_null(result.hit_entity) && result.hit_entity != e.ref {
                hit_entity := get_entity(result.hit_entity);
                if hit_entity == context.ball {
                    e.holding_entity = hit_entity.ref;
                }
            }
            request.channels = ALL_RAY_CHANNELS;
            request.hit_back_face = true;
            request.flip_back_face_hit_normal = true;
            result = .{};
            if raycast(*request, *result) && !is_null(result.hit_entity) && result.hit_entity != e.ref {
                hit_entity := get_entity(result.hit_entity);
                if is_set(*hit_entity.flags, .DOOR_THINK) {
                    set(*hit_entity.flags, .DOOR_RECEIVED_INTERACTION);
                    hit_entity.door.interaction_location = e.center;
                }
            }
        }
        unset(*e.flags, .USE_INTERACTION_QUEUED);
    }
    holding_entity = try_get_entity(*e.holding_entity);
    if holding_entity != null {
        look_dir := look_direction(e);
        right_dir := normalize(cross(look_dir, WORLD_UP));
        up_dir := normalize(cross(look_dir, -right_dir));
        // todo: restore physics
        unset(*holding_entity.flags, .MOVED_BY_PHYSICS);
        unset(*holding_entity.flags, .APPLY_GRAVITY);
        holding_entity.collision_channels = 0;
        holding_entity.center = look_origin(e) + look_direction(e) * 15.0;
        holding_entity.velocity = .{};
        holding_entity.angular_velocity = .{};
    }
}

door_think :: (using e: *Entity) {
    if door.state == .CLOSED || door.state == .OPEN_POSITIVE || door.state == .OPEN_NEGATIVE {
        door.rotation_distance = 0;
        door.pivot_location = center + door.pivot_local_offset.x * axes.right + door.pivot_local_offset.y * axes.fore * door.pivot_local_offset.z * axes.up;
        if is_set(*flags, .DOOR_RECEIVED_INTERACTION) {
            if door.state == .CLOSED {
                toward_interaction := door.interaction_location - center;
                in_positive_direction := dot(toward_interaction, axes.fore) > 0;
                door.state = ifx in_positive_direction then .OPENING_POSITIVE else .OPENING_NEGATIVE;
            } else if door.state == .OPEN_POSITIVE {
                door.state = .CLOSING_NEGATIVE;
            } else {
                door.state = .CLOSING_POSITIVE;
            }
            unset(*flags, .DOOR_RECEIVED_INTERACTION);
        }
    } else {
        rotation_direction: float;
        end_state: type_of(door.state);
        end_orientation: Quaternion;

        if door.state == .OPENING_POSITIVE {
            end_state = .OPEN_POSITIVE;
            rotation_direction = 1.0;
            end_orientation = door.closed_orientation;
            rotate(*end_orientation, door.pivot_axis, door.rotation_angle * rotation_direction);
        } else if door.state == .OPENING_NEGATIVE {
            end_state = .OPEN_NEGATIVE;
            rotation_direction = -1.0;
            end_orientation = door.closed_orientation;
            rotate(*end_orientation, door.pivot_axis, door.rotation_angle * rotation_direction);
        } else if door.state == .CLOSING_POSITIVE {
            end_state = .CLOSED;
            rotation_direction = 1.0;
            end_orientation = door.closed_orientation;
        } else {
            end_state = .CLOSED;
            rotation_direction = -1.0;
            end_orientation = door.closed_orientation;
        }

        rotation_delta := door.rotation_speed * delta_time;
        door.rotation_distance += rotation_delta;
        rotation_delta_signed := rotation_delta * rotation_direction;

        if door.rotation_distance >= door.rotation_angle {
            set_orientation(e, end_orientation);
            door.state = end_state;
            if (door.state == .OPEN_POSITIVE || door.state == .OPEN_NEGATIVE) {
                if e == context.door {
                    set(*context.ai_guy.flags, .DOOR_RECEIVED_INTERACTION);
                } else if e == context.ai_guy {
                    set(*context.door.flags, .DOOR_RECEIVED_INTERACTION);
                }
                if door.auto_reset_to_closed {
                    door.state = .CLOSED;
                    orientation = door.closed_orientation;
                }
            }
        } else {
            rotate(e, door.pivot_axis, rotation_delta_signed);
        }

        new_pivot_location := center + door.pivot_local_offset.x * axes.right + door.pivot_local_offset.y * axes.fore * door.pivot_local_offset.z * axes.up;
        toward_constraint := door.pivot_location - new_pivot_location;
        center += toward_constraint;
    }
}