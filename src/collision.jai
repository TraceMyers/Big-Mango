
// todo: it's convenient to clamp positions to the bounds of the collision grid so that the game doesn't have to crash
// when things go outside the bounds (and it's convenient for aabb projection), but some handling needs to be done to make sure that doesn't happen often. otherwise,
// a situation might occur where entities that are pretty far apart are bunched up into the edge cells, overpopulating them.
// todo: find a way to capture all declaration names and types in a block and export it to a struct, then insert
// code that copies all of the values of the block into the struct.

// world size: 2000 x 2000
// cell size: 10 x 10 
// world cell counts: 200 x 200 = 80_000

// todo: woops I made the whole collision grid using backing data indices to represent entities, when I need to be using
// reference indices. this problem comes to light when an entity is deleted.
// note: i made the thing with the specific rule that backing data indices don't persist across frames, which is why the Entity_Ref exists and I forgot about the importance of it this whole time.

// note:
// quickest path to fun: 
// - pick up object
// - throw object
// - automatic door
// - human moves through door if open
// - physics button controlling automatic door
// - throw object at button

AABB_OVERLAP_BUFFER :: 1.0;
INVALID_COLLISION_GROUP : s16 : S16_MAX;
PHYSICS_FIXED_TIME_STEP :: 1.0 / 240.0;
DRAW_COLLISION_MESHES :: BUILDVAR_COLLISION_DEBUG;

COLLISION_VELOCITY_ITERATION_COUNT :: 5;
COLLISION_POSITION_ITERATION_COUNT :: 8;
COLLISION_MAX_CORRECTION :: 1.0;
COLLISION_OVERLAP_TOLERANCE :: 0.001;
COLLISION_IMPULSE_DAMPING :: 0.95;
COLLISION_POSITION_CORRECTION_DAMPING :: 0.25;
Z_KILL_FLOOR :: -1000.0;

DEFAULT_LINEAR_IMPULSE_DURATION :: 1.0 / 90.0;

#if BUILDVAR_COLLISION_DEBUG {
    collision_assert :: assert;
} else {
    collision_assert :: (b: bool) #expand {}
}

_collision :: (stage: Boot_Stage) -> bool {
    if stage == .STARTUP {
        // bump_allocator_initialize(*collisions_allocator, heaps_tracking_array_ct := 16);
        // program_runtime_allocate(*collision_group_indices, ENTITY_MAX_COUNT);
        // for *collision_group_indices {
        //     it.* = INVALID_COLLISION_GROUP;
        // }
        array_reserve(*altered_cells, 4096);
    }
    return true;
}

solve_contacts :: () {
    scope_timer();

    entity_ct := get_entity_count();
    if entity_ct < 2 {
        return;
    }

    time_step_accumulator += delta_time;
    time_step_count := (time_step_accumulator / PHYSICS_FIXED_TIME_STEP).(s32);
    if time_step_count <= 0 {
        return;
    }

    // draw_collision_grid(context.player_entity.center.z - context.player_entity.shape.half_height, .{b=1});

    update_collision_grid_cell_occupations();

    // for any cells that were altered, shrink occupation allocations to be inline if it fits
    for altered_cells {
        collision_grid_cell_flags[it] &= ~.JUST_ALTERED;
        rectify_collision_cell_allocation(it);
    }

    warm_start_contacts();
    array_reset_keeping_memory(*contact_pairs);
    solve_contacts_broad_phase(time_step_count);
    solve_contacts_narrow_phase(time_step_count);

    for 0..entity_ct-1 {
        lfa_unset_multiple(*entity_flags[it], TRANSIENT_COLLISION_FLAGS);
    }
}

get_entities_in_overlap_group :: (group: []Pair(s16), out_entities: *[..]s16) {
    entity_ct := get_entity_count();
    set_capacity(*seen_entity_in_group, entity_ct);
    unset_all(*seen_entity_in_group);
    for group {
        if !bit_is_set(*seen_entity_in_group, it.a) {
            array_add(out_entities, it.a);
            set_bit(*seen_entity_in_group, it.a);
        }
        if !bit_is_set(*seen_entity_in_group, it.b) {
            array_add(out_entities, it.b);
            set_bit(*seen_entity_in_group, it.b);
        }
    }
}

remove_entity_from_collision_grid :: (ref: Entity_Ref) {
    i := entity_patch_layer[ref.index];
    assert(ref.id == entity_patch_infos[i].id);
    hash_upper := collision_cell_hashes[i] >> 32;
    grid_pos_min := collision_grid_index_to_grid_position(xx hash_upper);
    hash_lower := collision_cell_hashes[i] & 0xffff_ffff;
    grid_pos_max := collision_grid_index_to_grid_position(xx hash_lower);
    collision_grid_iterate(xx i, *altered_cells, grid_pos_min, grid_pos_max, .{}, remove_from_collision_cell);
    collision_cell_hashes[i] = 0xffff_ffff_ffff_ffff;
}

update_collision_grid_cell_occupations :: () {
    defer array_reset_keeping_memory(*altered_cells);

    scope_timer();
    entity_ct := get_entity_count();

    // collision_overlap_group_changed: Bit_Array(1);
    // collision_overlap_group_changed.items.allocator = temp;
    // set_capacity(*collision_overlap_group_changed, collision_overlap_groups.items.count);
    // unset_all(*collision_overlap_group_changed);

    for 0..entity_ct-1 {
        if entity_collision_channels[it] == 0 {
            continue;
        }
        self_body := *entity_collision_bodies[it];
        self_aabb := get_aabb_at(it);

        grid_pos_min := world_to_collision_grid_position(self_aabb.center.xy - self_aabb.extent.xy);
        grid_pos_max := world_to_collision_grid_position(self_aabb.center.xy + self_aabb.extent.xy);

        hash_upper := collision_grid_index(grid_pos_min);
        hash_lower := collision_grid_index(grid_pos_max);
        hash : s64 = (hash_upper.(s64) << 32) | hash_lower;

        if collision_cell_hashes[it] != hash {
            if collision_cell_hashes[it] != -1 {
                remove_entity_from_collision_grid(entity_ref(it));
            }
            collision_grid_iterate(xx it, *altered_cells, grid_pos_min, grid_pos_max, .{}, add_to_collision_cell);
            collision_cell_hashes[it] = hash;
            lfa_set(*entity_flags[it], .CHANGED_CELL_OCCUPATIONS);
        }

        // this is just a convenient place to get this part out of the way. while already iterating to change the cell occupations, go ahead and make sure entities that have moved are removed from their collision group, so they have to update their overlaps.
        // NOTE: could allow things to slowly overlap
        // prev_loc_dist_sq := distance_squared(self_body.center, self_body.previous_center);
        // if prev_loc_dist_sq > 0 && collision_group_indices[it] != INVALID_COLLISION_GROUP {
        //     overlap_group := *collision_overlap_groups[collision_group_indices[it]];
        //     for overlap_group.* {
        //         collision_group_indices[it.a] = INVALID_COLLISION_GROUP;
        //         collision_group_indices[it.b] = INVALID_COLLISION_GROUP;
        //     }
        //     array_reset(overlap_group);

        //     // TODO: make overlap group islanding work
        //     // set_bit(*collision_overlap_group_changed, collision_group_indices[it]);
        //     // entity_index := it;
        //     // for #v2 < 0..overlap_group.count-1 {
        //     //     overlap_pair := overlap_group.*[it];
        //     //     if overlap_pair.a == entity_index {
        //     //         array_unordered_remove_by_index(overlap_group, it);
        //     //         entity_collision_bodies[overlap_pair.b].collision_flags |= .NEED_CHECK_IF_IN_OVERLAP_GROUP;
        //     //     } else if overlap_pair.b == entity_index {
        //     //         array_unordered_remove_by_index(overlap_group, it);
        //     //         entity_collision_bodies[overlap_pair.a].collision_flags |= .NEED_CHECK_IF_IN_OVERLAP_GROUP;
        //     //     }
        //     // }
        //     // collision_group_indices[it] = INVALID_COLLISION_GROUP;
        // }
    }

    // when entities move and remove themselves from their overlap group, this potentially has the knock-on effect of taking other entities out of the group, if they were in the group only due to those removed overlaps.
    // for e : 0..entity_ct-1 {
    //     in_a_group := collision_group_indices[e] != INVALID_COLLISION_GROUP;
    //     some_of_my_overlaps_removed := (entity_collision_bodies[e].collision_flags & .NEED_CHECK_IF_IN_OVERLAP_GROUP) != 0;
    //     if in_a_group && some_of_my_overlaps_removed {
    //         overlap_group := *collision_overlap_groups[collision_group_indices[e]];
    //         found_overlap: bool;
    //         for *(overlap_group.*) {
    //             if it.a == e || it.b == e {
    //                 found_overlap = true;
    //                 break;
    //             }
    //         }
    //         if !found_overlap {
    //             collision_group_indices[e] = INVALID_COLLISION_GROUP;
    //         }
    //     }
    // }

    // initial_group_count := get_count(*collision_overlap_group_changed);

    // remove empty groups
    // if collision_overlap_groups.items.count > 0 {
    //     for *collision_overlap_groups.items {
    //         if is_item_in_use(*collision_overlap_groups, it_index) && it.count == 0 {
    //             array_reset(it);
    //             return_item(*collision_overlap_groups, it_index);
    //         }
    //     }
    //     // todo: make overkap group islanding work
    //     // for *collision_overlap_groups.items {
    //     //     if is_item_in_use(*collision_overlap_groups, it_index) 
    //     //     && it_index < initial_group_count 
    //     //     && bit_is_set(*collision_overlap_group_changed, it_index) {
    //     //         separate_collision_group_islands(xx it_index);
    //     //     }
    //     // }
    // }
}

// absorb_overlap_group :: (collision_group_indices: *[]s16, absorbing_group: s16, absorbed_group: s16) {
//     collision_assert(absorbing_group != absorbed_group);
//     fat_group := *collision_overlap_groups[absorbing_group];
//     dead_group := *collision_overlap_groups[absorbed_group];
//     array_append(fat_group, dead_group.*);
//     for dead_group.* {
//         collision_group_indices.*[it.a] = absorbing_group;
//         collision_group_indices.*[it.b] = absorbing_group;
//         array_add(fat_group, it);
//     }
//     array_reset(dead_group);
//     return_item(*collision_overlap_groups, absorbed_group);
// }

solve_contacts_broad_phase :: (time_step_count: s32) {
    scope_timer();
    entity_ct := get_entity_count();

    iteration_overlaps := temp_dynamic_array(Contact_Pair, 4096);

    find_overlaps_data: Find_Overlaps_Data;
    set_capacity(*find_overlaps_data.already_overlapped, entity_ct);

    total_time_step := PHYSICS_FIXED_TIME_STEP * time_step_count.(float);

    // todo: parallelizing this?
    for e : 0..entity_ct-1 {
        if entity_collision_channels[e] == 0 {
            continue;
        }
        // if collision_group_indices[e] != INVALID_COLLISION_GROUP {
        //     entity_collision_bodies[e].collision_flags |= .SKIPPED_GRID_ITERATE;
        //     continue;
        // }

        // moved in grid: movers take responsibility for generating new overlaps
        array_reset_keeping_memory(*iteration_overlaps);

        unset_all(*find_overlaps_data.already_overlapped);
        find_overlaps_data.collision_overlaps = *iteration_overlaps;

        collision_grid_iterate(xx e, total_time_step, *find_overlaps_data, find_overlaps_in_cell);
        if iteration_overlaps.count == 0 {
            continue;
        }

        array_append(*contact_pairs, iteration_overlaps);

        // add_to_group := collision_group_indices[e];
        // for iteration_overlaps {
        //     add_to_group = min(add_to_group, collision_group_indices[it.b]);
        // }
        
        // if add_to_group == INVALID_COLLISION_GROUP {
        //     new_group_index := request_item(*collision_overlap_groups);
        //     collision_assert(new_group_index != INVALID_COLLISION_GROUP);
        //     new_group := *collision_overlap_groups[new_group_index];
        //     array_resize(new_group, iteration_overlaps.count);
        //     copy_array(new_group.*, iteration_overlaps);
        //     collision_group_indices[e] = xx new_group_index;
        //     for *(new_group.*) {
        //         collision_group_indices[it.b] = xx new_group_index;
        //     }
        // }
        // else {
        //     existing_group := *collision_overlap_groups[add_to_group];
        //     if collision_group_indices[e] != INVALID_COLLISION_GROUP && collision_group_indices[e] != add_to_group {
        //         absorb_overlap_group(*collision_group_indices, add_to_group, collision_group_indices[e]);
        //     }
        //     collision_group_indices[e] = add_to_group;

        //     for iteration_overlaps {
        //         array_add(existing_group, it);
        //         if collision_group_indices[it.b] == INVALID_COLLISION_GROUP {

        //         } else if collision_group_indices[it.b] != add_to_group {
        //             absorb_overlap_group(*collision_group_indices, add_to_group, collision_group_indices[it.b]);
        //         }
        //         collision_group_indices[it.b] = add_to_group;
        //     }
        // }
    }
}

solve_contacts_narrow_phase :: (time_step_count: s32) {
    scope_timer();

    entities_in_group: [..]s16;
    array_reserve(*entities_in_group, 2048);

    for 0..time_step_count-1 {
        defer time_step_accumulator -= PHYSICS_FIXED_TIME_STEP;
        apply_impulses();
        solve_contact_velocities();
        move_stuff(PHYSICS_FIXED_TIME_STEP);
        solve_contact_positions();
    }
}

apply_impulses :: () {
    entity_ct := get_entity_count();
    for 0..entity_ct-1 {
        body := get_body_at(it);

        if !lfa_is_set(*entity_flags[it], .MOVED_BY_PHYSICS) {
            continue;
        }
        if lfa_is_set(*entity_flags[it], .APPLY_GRAVITY) {
            body.velocity.z -= get_physics_properties_at(it).gravity_accel * PHYSICS_FIXED_TIME_STEP;
        }

        impulses := get_linear_impulses_at(it);
        if impulses.count > 0 {
            switch_break();
            for *impulses {
                impulse_time_step := min(it.time_remaining, PHYSICS_FIXED_TIME_STEP);
                // a = f/m
                prev_velocity := body.velocity;
                time_over_mass := body.inv_mass * impulse_time_step;
                body.velocity += it.force * time_over_mass;
                it.time_remaining -= impulse_time_step + VERY_SMALL_NUMBER; // make sure we pass zero
            }
            clear_completed_impulses_at(it); // todo: could just remove swap while iterating
        }
    }
}

solve_contact_velocities :: () {
    // solve for velocity
    for 0..COLLISION_VELOCITY_ITERATION_COUNT-1 {
        for *pair : contact_pairs {
            body_a  := get_body_at(pair.a);
            axes_a  := get_axes_at(pair.a);
            props_a := get_physics_properties_at(pair.a);
            body_b  := get_body_at(pair.b);
            axes_b  := get_axes_at(pair.b);
            props_b := get_physics_properties_at(pair.b);

            contact_result: Contact_Result;
            if solve_potential_contact(body_a, axes_a, body_b, axes_b, PHYSICS_FIXED_TIME_STEP, *contact_result) {
                pair.contact_normal = contact_result.normal;

                a_to_point := contact_result.point - body_a.center;
                b_to_point := contact_result.point - body_b.center;
                a_angular_velocity := cross(body_a.angular_velocity, a_to_point);
                b_angular_velocity := cross(body_b.angular_velocity, b_to_point);

                velocity_a := body_a.velocity + a_angular_velocity;
                velocity_b := body_b.velocity + b_angular_velocity;

                if props_b.mass == IMMOVABLE_ENTITY_MASS {
                    body_a.velocity -= contact_result.normal * dot(body_a.velocity, contact_result.normal);
                } else {
                    effective_mass: float;
                    if body_a.shape.type == .SPHERE && body_b.shape.type == .SPHERE {
                        effective_mass = 1.0 / (body_a.inv_mass + body_b.inv_mass);
                    } else {
                        // todo: generalized effective mass calculation
                    }
                    relative_velocity := velocity_b - velocity_a;
                    speed_along_normal := dot(relative_velocity, contact_result.normal);

                    tangent_velocity := relative_velocity - speed_along_normal * contact_result.normal;
                    tangent_speed_sq := length_squared(tangent_velocity);
                    tangent_speed: float;
                    if tangent_speed_sq > VERY_SMALL_NUMBER {
                        tangent_speed = sqrt(tangent_speed_sq);
                        pair.contact_tangent = tangent_velocity / tangent_speed;
                    } else {
                        pair.contact_tangent = .{};
                    }

                    friction_impulse_magnitude := -tangent_speed * effective_mass;
                    normal_impulse_magnitude := speed_along_normal * effective_mass;

                    normal_impulse_magnitude, friction_impulse_magnitude = feed_contact_impulse(pair, normal_impulse_magnitude, friction_impulse_magnitude);

                    friction_impulse := pair.contact_tangent * friction_impulse_magnitude;
                    normal_impulse := normal_impulse_magnitude * contact_result.normal;
                    total_impulse := (normal_impulse + friction_impulse) * COLLISION_IMPULSE_DAMPING;

                    body_a.velocity += total_impulse * body_a.inv_mass;
                    body_b.velocity -= total_impulse * body_b.inv_mass;

                    if lfa_is_set(*entity_flags[pair.a], .PHYSICS_DRIVEN_ROTATION) {
                        body_a.angular_velocity += inv_inertia_tensors[pair.a] * cross(a_to_point, total_impulse);
                    }
                    if lfa_is_set(*entity_flags[pair.b], .PHYSICS_DRIVEN_ROTATION) {
                        body_b.angular_velocity += inv_inertia_tensors[pair.b] * cross(b_to_point, total_impulse);
                    }
                }
            }
        }
    }
}

solve_contact_positions :: () {
// correct positions
    for 0..COLLISION_POSITION_ITERATION_COUNT-1 {
        for pair : contact_pairs {
            body_a  := get_body_at(pair.a);
            axes_a  := get_axes_at(pair.a);
            props_a := get_physics_properties_at(pair.a);
            body_b  := get_body_at(pair.b);
            axes_b  := get_axes_at(pair.b);
            props_b := get_physics_properties_at(pair.b);

            contact_result: Contact_Result;
            if solve_potential_contact(body_a, axes_a, body_b, axes_b, PHYSICS_FIXED_TIME_STEP, *contact_result) {
                if props_b.mass == IMMOVABLE_ENTITY_MASS {
                    force := clamp(COLLISION_POSITION_CORRECTION_DAMPING * (contact_result.depth - COLLISION_OVERLAP_TOLERANCE), 0, COLLISION_MAX_CORRECTION);
                    impulse := contact_result.normal * force;
                    body_a.center += impulse;
                } else {
                    force := clamp(COLLISION_POSITION_CORRECTION_DAMPING * (contact_result.depth - COLLISION_OVERLAP_TOLERANCE), 0, COLLISION_MAX_CORRECTION);
                    impulse := contact_result.normal * force;
                    inv_mass_sum := 1 / (props_a.mass + props_b.mass);
                    impulse_a :=  impulse * (body_a.inv_mass * inv_mass_sum);
                    impulse_b := -impulse * (body_b.inv_mass * inv_mass_sum);
                    body_a.center += impulse_a;
                    body_b.center += impulse_b;
                }
            }
        }
    }
}

warm_start_contacts :: () {
    entity_ct := get_entity_count();
    for pair : contact_pairs {
        if pair.a >= entity_ct || pair.b >= entity_ct {
            continue;
        }
        if get_frame_counter_at(pair.a) > 1 && get_frame_counter_at(pair.b) > 1 {
            body_a := get_body_at(pair.a);
            body_b := get_body_at(pair.b);

            normal_impulse := pair.contact_normal * (pair.normal_impulse_sum * COLLISION_IMPULSE_DAMPING);
            body_a.velocity += normal_impulse * body_a.inv_mass;
            body_b.velocity -= normal_impulse * body_b.inv_mass;
            
            // todo: warm start angular
        }
    }
}

// TODO: make overlap islanding work. doesn't work
// whenever a group may have islands in itself, this can be run to separate the islands into their own groups
// separate_collision_group_islands :: (group_index: s32) {
//     auto_release_temp();
//     group := *collision_overlap_groups[group_index];
//     if group.count == 0 {
//         return;
//     }

//     entities_in_group := temp_dynamic_array(s16, group.count);
//     get_entities_in_overlap_group(group.*, *entities_in_group); 

//     for e : entities_in_group {
//         entity_collision_bodies[e].island_grouping_index = INVALID_COLLISION_GROUP;
//     }

//     // logic here doesn't work if INVALID_COLLISION_GROUP isn't at least larger than max(number of collision pairs, number of islands)
//     collision_assert(INVALID_COLLISION_GROUP == S16_MAX);

//     group_index_counter : s16 = 0;
//     for pair : group.* {
//         a_group := *entity_collision_bodies[pair.a].island_grouping_index;
//         incremented_counter: bool;
//         if a_group.* == INVALID_COLLISION_GROUP {
//             a_group.* = group_index_counter;
//             group_index_counter += 1;
//             incremented_counter = true;
//         }
//         b_group := *entity_collision_bodies[pair.b].island_grouping_index;
//         if b_group.* < a_group.* {
//             a_group.* = b_group.*;
//             if incremented_counter { // don't think this works
//                 group_index_counter -= 1;
//             }
//         } else {
//             b_group.* = a_group.*;
//         }
//     }

//     group_old := duplicate(group.*, temp);
//     array_reset_keeping_memory(group);

//     true_group_indices := alloc_array(s16, group_old.count, temp);
//     for *true_group_indices {
//         it.* = INVALID_COLLISION_GROUP;
//     }
//     true_group_indices[0] = xx (group - collision_overlap_groups.items.data);

//     for group_old {
//         collision_assert(entity_collision_bodies[it.a].island_grouping_index == entity_collision_bodies[it.b].island_grouping_index);
//         temp_index := entity_collision_bodies[it.a].island_grouping_index;
//         true_group_index := true_group_indices[temp_index];
//         if true_group_index == INVALID_COLLISION_GROUP {
//             true_group_index = xx request_item(*collision_overlap_groups);
//             true_group_indices[temp_index] = true_group_index;
//             collector := *collision_overlap_groups[true_group_index];
//             array_reserve(collector, 32);
//         }
//         collector := *collision_overlap_groups[true_group_index];
//         collision_assert(true_group_index >= 0 && true_group_index < collision_overlap_groups.items.count);
//         array_add(collector, it);
//         collision_group_indices[it.a] = xx true_group_index;
//         collision_group_indices[it.b] = xx true_group_index;
//     }
// }

solve_potential_contact :: (body_a: Collision_Body, axes_a: Axes, body_b: Collision_Body, axes_b: Axes, time_step: float, out_result: *Contact_Result) -> bool {
    shape_a := *body_a.shape;
    shape_b := *body_b.shape;
    if shape_a.type == {
    case .SPHERE;
        if shape_b.type == {
        case .SPHERE;
            #if BUILDVAR_COLLISION_DEBUG {
                return Procedure_Capture_Duplicate.solve_potential_contact_sphere_sphere(body_a, axes_a, body_b, axes_b, time_step, out_result);
            } else {
                return solve_potential_contact_sphere_sphere(body_a, axes_a, body_b, axes_b, time_step, out_result);
            }
        case .CAPSULE;
        case .RECT;
            #if BUILDVAR_COLLISION_DEBUG {
                return Procedure_Capture_Duplicate.solve_potential_contact_sphere_rect(body_a, axes_a, body_b, axes_b, time_step, out_result);
            } else {
                return solve_potential_contact_sphere_rect(body_a, axes_a, body_b, axes_b, time_step, out_result);
            }
        case .BOX;
        case .AABB;
        case .HALF_SPACE;
        }
    case .CAPSULE;
        if shape_b.type == {
        case .SPHERE;
        case .CAPSULE;
        case .RECT;
        case .BOX;
        case .AABB;
        case .HALF_SPACE;
        }
    case .RECT;
        if shape_b.type == {
        case .SPHERE;
        case .CAPSULE;
        case .RECT;
        case .BOX;
        case .AABB;
        case .HALF_SPACE;
        }
    case .BOX;
        if shape_b.type == {
        case .SPHERE;
        case .CAPSULE;
        case .RECT;
        case .BOX;
        case .AABB;
        case .HALF_SPACE;
        }
    case .AABB;
        if shape_b.type == {
        case .SPHERE;
        case .CAPSULE;
        case .RECT;
        case .BOX;
        case .AABB;
        case .HALF_SPACE;
        }
    case .HALF_SPACE;
        if shape_b.type == {
        case .SPHERE;
        case .CAPSULE;
        case .RECT;
        case .BOX;
        case .AABB;
        case .HALF_SPACE;
        }
    }
    return false;
}

solve_potential_contact_sphere_sphere :: (body_a: Collision_Body, axes_a: Axes, body_b: Collision_Body, axes_b: Axes, time_step: float, out_result: *Contact_Result) -> bool {
    sphere_a    := *body_a.shape.sphere;
    sphere_b    := *body_b.shape.sphere;

    radius_sum := sphere_a.radius + sphere_b.radius;
    diff := body_a.center - body_b.center;
    dist_sq := length_squared(diff);

    if dist_sq < VERY_SMALL_NUMBER {
        out_result.normal = WORLD_RIGHT;
        out_result.point = body_a.center - out_result.normal * sphere_a.radius;
        out_result.depth = radius_sum;
        return true;
    }
    
    dist := sqrt(dist_sq);
    out_result.normal = diff / dist;
    out_result.point = body_a.center - out_result.normal * sphere_a.radius;

    approach_speed := dot(out_result.normal, body_b.velocity - body_a.velocity);
    future_dist := dist - approach_speed * time_step;
    out_result.depth = radius_sum - future_dist;

    return out_result.depth > 0;
} @capture_body_as_struct

solve_potential_contact_sphere_rect :: (body_a: Collision_Body, axes_a: Axes, body_b: Collision_Body, axes_b: Axes, time_step: float, out_result: *Contact_Result) -> bool {
    sphere_a    := *body_a.shape.sphere;
    rect_b      := *body_b.shape.rect;

    center_diff := body_a.center - body_b.center;
    distance_along_normal := dot(center_diff, axes_b.fore);
    if distance_along_normal < VERY_SMALL_NUMBER {
        return false;
    }

    up_dist := clamp(dot(center_diff, axes_b.up), -rect_b.half_height, rect_b.half_height);
    right_dist := clamp(dot(center_diff, axes_b.right), -rect_b.half_width, rect_b.half_width);
    a_projected_onto_b := body_b.center + axes_b.up * up_dist + axes_b.right * right_dist;

    contact_diff := body_a.center - a_projected_onto_b;
    dist := distance(body_a.center, a_projected_onto_b);

    out_result.normal = contact_diff / dist;

    approach_speed := dot(out_result.normal, body_b.velocity - body_a.velocity);
    future_dist := dist - approach_speed * time_step;
    out_result.depth = sphere_a.radius - future_dist;

    return out_result.depth > 0;

} @capture_body_as_struct 

get_aabb_extent :: (shape: Collision_Shape, axis_fore: Vector3, axis_up: Vector3, axis_right: Vector3) -> Vector3 {
    if #complete shape.type == {
    case .NONE;
        assert(false);
        return .{};
    case .SPHERE;
        using shape.sphere;
        return .{radius, radius, radius};
    case .CAPSULE;
        using shape.capsule;
        segment_half_len := half_height - radius;
        segment_point := axis_up * segment_half_len;
        return abs(segment_point) + Vector3.{radius,radius,radius};
    case .RECT;
        using shape.rect;
        abs_point_1 := abs(axis_up * half_height + axis_right * half_width);
        abs_point_2 := abs(axis_up * half_height - axis_right * half_width);
        return max(abs_point_1, abs_point_2) + SMALL_NUMBER;
    case .BOX;
        using shape.box;
        height_vec := abs(axis_up * half_height);
        length_vec := abs(axis_fore * half_length);
        width_vec  := abs(axis_right * half_width);
        return max(height_vec, max(length_vec, width_vec));
    case .AABB;
        using shape.aabb;
        return .{half_width, half_length, half_height};
    case .HALF_SPACE;
        // you *can* have plane bounds in the case where the plane exactly aligns with an axis, but in that case
        // its bounds have area 0, which isn't useful for collision pruning.
        return .{FLOAT32_MAX, FLOAT32_MAX, FLOAT32_MAX};
    }
}

get_aabb :: inline (shape: Collision_Shape, position: Vector3, orientation: Quaternion, out_aabb: *AABB)  {
    axis_fore, axis_up, axis_right: Vector3 = ---;
    get_axes(orientation, *axis_fore, *axis_up, *axis_right);
    get_aabb(shape, position, axis_fore, axis_up, axis_right, out_aabb);
}

get_aabb :: inline (shape: Collision_Shape, position: Vector3, axis_fore: Vector3, axis_up: Vector3, axis_right: Vector3, out_aabb: *AABB) {
    out_aabb.center = position;
    out_aabb.extent = get_aabb_extent(shape, axis_fore, axis_up, axis_right);
}

get_aabb :: inline (body: *Collision_Body, axes: Axes) -> AABB {
    out_aabb : AABB = ---;
    out_aabb.center = body.center;
    out_aabb.extent = get_aabb_extent(body.shape, axes.fore, axes.up, axes.right);
    return out_aabb;
}

get_aabb_at :: inline (i: s64) -> AABB {
    axes := get_axes_at(i);
    return get_aabb(*entity_collision_bodies[i], axes);
}

collision_grid: []Collision_Grid_Allocation;
collision_grid_cell_flags: []Collision_Grid_Cell_Flags;
collision_grid_allocator: Nesting_Allocator(8);
collision_grid_origin: Vector2;
collision_grid_dimensions: Int_Vector2;
collision_cell_dimensions: Vector2;
inv_collision_cell_dimensions: Vector2;

time_step_accumulator := 0.0;

contact_pairs: [..]Contact_Pair;

// collision_group_indices: []s16;

seen_entity_in_group: Bit_Array(1);

color_group_random_state: Random_State;
altered_cells: [..]s32;
