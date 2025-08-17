
update_thinks :: () {
    for *e : context.world.entities {
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
                if result.hit_entity == context.world.ball_ref {
                    e.holding_entity = result.hit_entity;
                }
            }

            if is_set(*e.flags, .CAN_INTERACT_WITH_GADGETS_IN_PROXIMITY) {
                result = .{};
                request.channels = .GADGET;
                request.hit_back_face = true;
                if raycast(*request, *result) && !is_null(result.hit_entity) && result.hit_entity != e.ref {
                    hit_entity := get_entity(result.hit_entity);
                    assert(is_set(*hit_entity.flags, .USES_GADGET));
                    if gadget_can_take_interaction(hit_entity, e) {
                        add_gadget_interaction(hit_entity, .{input=.{source_entity=e.ref, source_location=e.center}});
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

    take_interaction: *Gadget_Interaction;

    if gadget_can_respond_to_interaction(e) {
        for *e.gadget_interactions.field {
            if per_frame_time >= it.end_time {
                take_interaction = it;
                break;
            }

            time_passed := per_frame_time - it.begin_time;
            time_total := it.end_time - it.begin_time;
            norm_time := clamp(time_passed / time_total, 0.0, 1.0);
            start_location := it.source_location;
            end_location := e.center;
            position_on_path := start_location + (end_location - start_location) * norm_time;

            move_norm := normalize(end_location - start_location);
            draw_line(position_on_path - move_norm * 2.5, position_on_path + move_norm * 2.5, .{r=1,g=1,b=1});
            draw_sphere(position_on_path, 0.38, .{r=1,g=1,b=1}, .LOW);
        }
    }

    gadget_working, emit_interact_to_children: bool;
    if e.gadget_type == {
    case .DOOR;
        gadget_working, emit_interact_to_children = gadget_door_think(e, take_interaction);
    case .BUTTON;
        gadget_working, emit_interact_to_children = gadget_button_think(e, take_interaction);
    }

    if take_interaction != null {
        index := take_interaction - e.gadget_interactions.field.data;
        remove_gadget_interaction_at(e, index);
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
                delay := get_gadget_interaction_delay_with_gadget(e, child);
                add_gadget_interaction(child, .{input=.{e.ref, e.center, delay, 0}});
            }
        }
    }
}

gadget_can_respond_to_interaction :: (using e: *Entity) -> bool {
    if #complete e.gadget_type == {
    case .DOOR;
        return door.state == .CLOSED || door.state == .OPEN_POSITIVE || door.state == .OPEN_NEGATIVE;
    case .BUTTON;
        return true;
    }
}

gadget_door_think :: (using e: *Entity, interaction: *Gadget_Interaction) -> working: bool, emit_interact_to_children: bool {
    working: bool;
    emit_interact: bool;

    if interaction != null {
        working = true;
        door.rotation_distance = 0;
        door.pivot_location = center + door.pivot_local_offset.x * axes.right + door.pivot_local_offset.y * axes.fore * door.pivot_local_offset.z * axes.up;
        if door.state == .CLOSED {
            toward_interaction := interaction.source_location - center;
            in_positive_direction := dot(toward_interaction, axes.fore) > 0;
            door.state = ifx in_positive_direction then .OPENING_POSITIVE else .OPENING_NEGATIVE;
        } else if door.state == .OPEN_POSITIVE {
            door.state = .CLOSING_NEGATIVE;
        } else if door.state == .OPEN_NEGATIVE {
            door.state = .CLOSING_POSITIVE;
        }
    }

    if door.state == .CLOSED || door.state == .OPEN_POSITIVE || door.state == .OPEN_NEGATIVE {
        // $rm_micro_optimization: don't have to set these every frame.
        working = false;
        door.rotation_distance = 0;
        door.pivot_location = center + door.pivot_local_offset.x * axes.right + door.pivot_local_offset.y * axes.fore * door.pivot_local_offset.z * axes.up;
    } else {
        working = true;
        rotation_direction: float;
        end_state: type_of(door.state);
        end_orientation: Quaternion;
        begin_orientation: Quaternion;

        if door.state == .OPENING_POSITIVE {
            end_state = .OPEN_POSITIVE;
            rotation_direction = 1.0;
            begin_orientation = door.closed_orientation;
            end_orientation = door.closed_orientation;
            rotate(*end_orientation, door.pivot_axis, door.rotation_angle * rotation_direction);
        } else if door.state == .OPENING_NEGATIVE {
            end_state = .OPEN_NEGATIVE;
            rotation_direction = -1.0;
            begin_orientation = door.closed_orientation;
            end_orientation = door.closed_orientation;
            rotate(*end_orientation, door.pivot_axis, door.rotation_angle * rotation_direction);
        } else if door.state == .CLOSING_POSITIVE {
            end_state = .CLOSED;
            rotation_direction = 1.0;
            begin_orientation = door.closed_orientation;
            end_orientation = door.closed_orientation;
            rotate(*begin_orientation, door.pivot_axis, -door.rotation_angle * rotation_direction);
        } else { // CLOSING_NEGATIVE
            end_state = .CLOSED;
            rotation_direction = -1.0;
            begin_orientation = door.closed_orientation;
            end_orientation = door.closed_orientation;
            rotate(*begin_orientation, door.pivot_axis, -door.rotation_angle * rotation_direction);
        }

        rotation_delta := door.rotation_speed * delta_time;
        door.rotation_distance += rotation_delta;
        norm_distance := max(door.rotation_distance / door.rotation_angle, 0);

        if norm_distance >= 1.0 {
            set_orientation(e, end_orientation);
            door.state = end_state;
            emit_interact = true;
            if (door.state == .OPEN_POSITIVE || door.state == .OPEN_NEGATIVE) {
                if door.auto_reset_to_closed {
                    door.state = .CLOSED;
                    orientation = door.closed_orientation;
                }
            }
        } else {
            // by doing an interp rotate rather than a stepped rotate, we avoid accruing float error over our plentiful harvest of frames
            interp_rotate(e, begin_orientation, end_orientation, norm_distance);
        }

        new_pivot_location := center + door.pivot_local_offset.x * axes.right + door.pivot_local_offset.y * axes.fore * door.pivot_local_offset.z * axes.up;
        toward_constraint := door.pivot_location - new_pivot_location;
        center += toward_constraint;
    }

    return working, emit_interact;
}

gadget_button_think :: (using e: *Entity, interaction: *Gadget_Interaction) -> working: bool, emit_interact_to_children: bool {
    working: bool;
    emit_interact: bool;

    if interaction != null {
        norm2_cycle_time_cur := clamp((button.cycle_time_cur / button.cycle_time_max) * 2.0, 0, 2);
        if norm2_cycle_time_cur < 1.0 {
            norm2_cycle_time_cur += 0.75;
        } else {
            norm2_cycle_time_cur = min(2.0 - norm2_cycle_time_cur, 1.0);
        }
        button.cycle_time_cur = norm2_cycle_time_cur * 0.5 * button.cycle_time_max;
    }

    if button.cycle_time_cur != 0 {
        working = true;

        havent_emitted_signal := button.cycle_time_cur < button.cycle_time_max * 0.5;
        button.cycle_time_cur += delta_time;
        should_emit_signal := button.cycle_time_cur >= button.cycle_time_max * 0.5;

        if havent_emitted_signal && should_emit_signal {
            emit_interact = true;
        }

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