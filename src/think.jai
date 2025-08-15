
update_thinks :: () {
    for *e : entities {
        if is_set(*e.flags, .PLAYER_ENTITY_THINK) {
            player_entity_think(e);
        }
        if is_set(*e.flags, .USES_GADGET) {
            gadget_think(e);
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

            request.channels = .DEFAULT;
            if raycast(*request, *result) && !is_null(result.hit_entity) && result.hit_entity != e.ref {
                hit_entity := get_entity(result.hit_entity);
                if hit_entity == context.ball {
                    e.holding_entity = hit_entity.ref;
                }
            }

            if is_set(*e.flags, .CAN_INTERACT_WITH_GADGETS) {
                result = .{};
                request.channels = .GADGET;
                request.hit_back_face = true;
                if raycast(*request, *result) && !is_null(result.hit_entity) && result.hit_entity != e.ref {
                    hit_entity := get_entity(result.hit_entity);
                    assert(is_set(*hit_entity.flags, .USES_GADGET));
                    if gadget_can_take_interaction(hit_entity, e) {
                        add_gadget_interaction(hit_entity, .{e.ref, e.center, 0});
                    }
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
        // todo: save and restore physics rather than forgetting it
        unset(*holding_entity.flags, .MOVED_BY_PHYSICS);
        unset(*holding_entity.flags, .APPLY_GRAVITY);
        holding_entity.collision_channels = 0;
        holding_entity.center = look_origin(e) + look_direction(e) * 15.0;
        holding_entity.velocity = .{};
        holding_entity.angular_velocity = .{};
    }
}

gadget_think :: (e: *Entity) {
    assert(e.gadget_type != 0);

    is_active := is_gadget_active(e);
    if !is_active {
        return;
    }

    gadget_working, emit_interact_to_children: bool;
    if e.gadget_type == {
    case .DOOR;
        gadget_working, emit_interact_to_children = gadget_door_think(e);
    case .BUTTON;
        gadget_working, emit_interact_to_children = gadget_button_think(e);
    }

    if gadget_working {
        set(*e.flags, .GADGET_WORKING);
    } else {
        unset(*e.flags, .GADGET_WORKING);
    }

    if emit_interact_to_children {
        for #v2 < 0..e.gadget_children.field.count-1 {
            child_ref := *e.gadget_children.field[it].entity;
            child := try_get_entity(child_ref);
            if !child {
                remove_gadget_child_at(e, it);
                continue;
            }
            if gadget_can_take_interaction(child, e, true) {
                add_gadget_interaction(child, .{e.ref, e.center, 0});
            }
        }
    }
}

gadget_door_think :: (using e: *Entity) -> working: bool, emit_interact_to_children: bool {
    working: bool;
    emit_interact: bool;

    if door.state == .CLOSED || door.state == .OPEN_POSITIVE || door.state == .OPEN_NEGATIVE {
        // $rm_optimization: don't have to set these every frame.
        working = false;
        door.rotation_distance = 0;
        door.pivot_location = center + door.pivot_local_offset.x * axes.right + door.pivot_local_offset.y * axes.fore * door.pivot_local_offset.z * axes.up;

        if gadget_interactions.field.count > 0 {
            working = true;
            interaction := *gadget_interactions.field[0];
            if door.state == .CLOSED {
                toward_interaction := interaction.source_location - center;
                in_positive_direction := dot(toward_interaction, axes.fore) > 0;
                door.state = ifx in_positive_direction then .OPENING_POSITIVE else .OPENING_NEGATIVE;
            } else if door.state == .OPEN_POSITIVE {
                door.state = .CLOSING_NEGATIVE;
            } else {
                door.state = .CLOSING_POSITIVE;
            }
            remove_gadget_interaction_at(e, 0);
            emit_interact = true;
        }
    } else {
        working = true;
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
        } else { // CLOSING_NEGATIVE
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

    return working, emit_interact;
}

gadget_button_think :: (using e: *Entity) -> working: bool, emit_interact_to_children: bool {
    working: bool;
    emit_interact: bool;

    // $todo: buttons can't work 100% correctly if they can't use a parent entity's location as a reference. this could be done
    // by just having a parent 'origin' object

    if gadget_interactions.field.count > 0 {
        interaction := *gadget_interactions.field[0];
        remove_gadget_interaction_at(e, 0);
        emit_interact = true;

        norm2_cycle_time_cur := clamp((button.cycle_time_cur / button.cycle_time_max) * 2.0, 0, 2);

        if norm2_cycle_time_cur < 1.0 {
            norm2_cycle_time_cur += 0.8;
        } else {
            norm2_cycle_time_cur = min(2.0 - norm2_cycle_time_cur, 1.0);
        }

        button.cycle_time_cur = norm2_cycle_time_cur * 0.5 * button.cycle_time_max;
    }

    if button.cycle_time_cur != 0 {
        working = true;

        button.cycle_time_cur += delta_time;
        norm2_cycle_time_cur := clamp((button.cycle_time_cur / button.cycle_time_max) * 2.0, 0, 2);

        norm_dist: float;
        if norm2_cycle_time_cur < 1.0 {
            norm_dist = norm2_cycle_time_cur;
        } else {
            norm_dist = min(2 - norm2_cycle_time_cur, 1.0);
        }

        button.cycle_time_cur = norm2_cycle_time_cur * 0.5 * button.cycle_time_max;
        offset := -WORLD_UP * (norm_dist * button.press_distance);

        for *e.meshes.field {
            if it.data.primitive_type == .CAPSULE {
                it.offset = offset;
                break;
            }
        }

        if norm2_cycle_time_cur == 2.0 {
            button.cycle_time_cur = 0;
        }
    }

    return working, emit_interact;
}