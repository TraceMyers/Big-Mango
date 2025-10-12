
// todo: it's convenient to clamp positions to the bounds of the collision grid so that the game doesn't have to crash
// when things go outside the bounds (and it's convenient for aabb projection), but some handling needs to be done to make sure that doesn't happen often. otherwise,
// a situation might occur where entities that are pretty far apart are bunched up into the edge cells, overpopulating them.
// todo: find a way to capture all declaration names and types in a block and export it to a struct, then insert
// code that copies all of the values of the block into the struct.

// world size: 2000 x 2000
// cell size: 10 x 10 
// world cell counts: 200 x 200 = 80_000

// later
// - planned jump; jumping is typically awkward. could I make decent way of doing jumps that isn't awkward but fits a real time first person thinky actionish vibe? closest thing I can think of is talos principle jump, but it's too puzzle-gamey. something in-between would be nice.
// - there should be a basketball court in at least one level, and it should make use of the following gameplay elements:
// (this is fun & cheap make-your-own-fun gameplay
//      - throwing ball into hoop (normal)
//      - throwing ball into hoop (using super throw)
//      - jumping up and dropping ball into hoop (using super jump)

AABB_OVERLAP_BUFFER :: 1.0;
PHYSICS_FIXED_TIME_STEP :: 1.0 / 240.0;
DRAW_COLLISION_MESHES :: BUILDVAR_COLLISION_DEBUG;

COLLISION_VELOCITY_ITERATION_COUNT :: 6;
COLLISION_POSITION_ITERATION_COUNT :: 8;
COLLISION_MAX_CORRECTION :: 10.0;
COLLISION_OVERLAP_TOLERANCE :: 0.001;
COLLISION_IMPULSE_DAMPING :: 0.8;
COLLISION_POSITION_CORRECTION_DAMPING :: 0.35;
Z_KILL_FLOOR :: -100.0;

#if BUILDVAR_COLLISION_DEBUG {
    collision_assert :: assert;
} else {
    collision_assert :: (b: bool) #expand {}
}

solve_contacts :: () {
    using context.world;
    scope_timer();

    // draw_collision_grid(10, .{b=1});

    time_step_accumulator += delta_time;
    time_step_count := (time_step_accumulator / PHYSICS_FIXED_TIME_STEP).(s32);
    if time_step_count <= 0 {
        return;
    }
    collision_frame += 1;
    time_step_accumulator -= PHYSICS_FIXED_TIME_STEP * time_step_count.(float);

    update_collision_grid_cell_occupations();

    // for any cells that were altered, shrink occupation allocations to be inline if it fits
    for altered_cells {
        collision_grid_cell_flags[it] &= ~.JUST_ALTERED;
        try_inline_collision_cell_allocation(it);
    }

    warm_start_contacts();
    array_reset_keeping_memory(*contact_pairs);
    solve_contacts_broad_phase(time_step_count);
    solve_contacts_narrow_phase(time_step_count);

    {
        TRANSIENT_COLLISION_FLAGS :: Entity_Flags.[.COLLIDING_WITH_SOMETHING, .CHANGED_CELL_OCCUPATIONS];
        for e : context.world.entities {
            unset_multiple(*e.flags, TRANSIENT_COLLISION_FLAGS);
        }
    }
}

remove_entity_from_collision_grid :: (e: *Entity) {
    using context.world;
    hash_upper := e.collision_cell_hash >> 32;
    grid_pos_min := collision_grid_index_to_grid_position(xx hash_upper);
    hash_lower := e.collision_cell_hash & 0xffff_ffff;
    grid_pos_max := collision_grid_index_to_grid_position(xx hash_lower);
    collision_grid_iterate(e.ref, *altered_cells, grid_pos_min, grid_pos_max, .{}, remove_from_collision_cell);
    e.collision_cell_hash = INVALID_COLLISION_CELL_HASH;
}

update_collision_grid_cell_occupations :: () {
    using context.world;
    defer array_reset_keeping_memory(*altered_cells);

    for *e : context.world.entities {
        if e.collision_channels == 0 {
            continue;
        }
        self_aabb := get_aabb(e);

        grid_pos_min := world_to_collision_grid_position(self_aabb.center.xy - self_aabb.extent.xy);
        grid_pos_max := world_to_collision_grid_position(self_aabb.center.xy + self_aabb.extent.xy);

        hash_upper := collision_grid_index(grid_pos_min);
        hash_lower := collision_grid_index(grid_pos_max);
        hash : s64 = (hash_upper.(s64) << 32) | hash_lower;

        if e.collision_cell_hash != hash {
            if e.collision_cell_hash != INVALID_COLLISION_CELL_HASH {
                remove_entity_from_collision_grid(e);
            }
            collision_grid_iterate(e.ref, *altered_cells, grid_pos_min, grid_pos_max, .{}, add_to_collision_cell);
            set(*e.flags, .CHANGED_CELL_OCCUPATIONS);
            e.collision_cell_hash = hash;
        }
    }
}

solve_contacts_broad_phase :: (time_step_count: s32) {
    using context.world;

    iteration_overlaps := temp_dynamic_array(Contact_Pair, 4096);

    find_overlaps_data: Find_Overlaps_Data;
    find_overlaps_data.already_overlapped.items.allocator = temp;
    set_capacity(*find_overlaps_data.already_overlapped, context.world.entity_ref_layer.items.count);

    total_time_step := PHYSICS_FIXED_TIME_STEP * time_step_count.(float);

    // todo: parallelize: each thread gets its own contact pairs array. that's really it.
    for *e : context.world.entities {
        if e.collision_channels == 0 {
            if is_set(*e.flags, .USES_EVENT_VOLUME) {
                if e.overlap_channels == 0 {
                    continue;
                }
            } else continue;
        }

        // moved in grid: movers take responsibility for generating new overlaps
        array_reset_keeping_memory(*iteration_overlaps);

        unset_all(*find_overlaps_data.already_overlapped);
        find_overlaps_data.collision_overlaps = *iteration_overlaps;

        collision_grid_iterate(e.ref, total_time_step, *find_overlaps_data, find_overlaps_in_cell);
        if iteration_overlaps.count == 0 {
            continue;
        }

        // todo: if I want non-aabb event volumes, I could put this logic into narrow phase solving only for non-aabb volumes
        if is_set(*e.flags, .USES_EVENT_VOLUME) {
            for pair : iteration_overlaps {
                found_existing_overlap: bool;
                for *overlap : e.event_volume.overlaps {
                    if pair.b == overlap.entity {
                        found_existing_overlap = true;
                        overlap.last_seen_on_frame = collision_frame;
                        break;
                    }
                }
                if !found_existing_overlap {
                    add_event_volume_overlap(e, pair.b);
                }
            }
        }

        if e.collision_channels != 0 {
            array_append(*contact_pairs, iteration_overlaps);
        }
    }
}

solve_contacts_narrow_phase :: (time_step_count: s32) {
    using context.world;

    for 0..time_step_count-1 {
        apply_impulses();
        solve_contact_velocities();
        move_stuff(PHYSICS_FIXED_TIME_STEP);
        solve_contact_positions();
        physics_frame += 1;
    }
}

apply_impulses :: () {
    using context.world;
    for *e : context.world.entities {
        if is_set(*e.flags, .APPLY_GRAVITY) {
            e.velocity.z -= e.physics_properties.gravity_accel * PHYSICS_FIXED_TIME_STEP;
        }
        if is_set(*e.flags, .MOVED_BY_PHYSICS) && e.linear_impulses.count > 0 {
            inv_mass := 1.0 / e.physics_properties.mass;
            for #v2 < *e.linear_impulses {
                impulse_time_step := min(it.time_remaining, PHYSICS_FIXED_TIME_STEP);
                // a = f/m
                prev_velocity := e.velocity;
                time_over_mass := impulse_time_step * inv_mass;
                e.velocity += it.force * time_over_mass;
                it.time_remaining -= impulse_time_step + VERY_SMALL_NUMBER; // make sure we pass zero
                if it.time_remaining <= 0 {
                    remove_linear_impulse_at(e, it_index);
                }
            }
        } else {
            remove_all_linear_impulses(e);
        }
    }
}

solve_contact_velocities :: () {
    using context.world;
    for 0..COLLISION_VELOCITY_ITERATION_COUNT-1 {
        for *pair : contact_pairs {
            entity_a := get_entity(pair.a);
            entity_b := get_entity(pair.b);

            contact_result: Contact_Result;
            if solve_potential_contact(entity_a.body, entity_a.axes, entity_b.body, entity_b.axes, PHYSICS_FIXED_TIME_STEP, *contact_result) {

                pair.contact_normal = contact_result.normal;

                a_to_point := contact_result.point - entity_a.center;
                b_to_point := contact_result.point - entity_b.center;

                a_angular_velocity := cross(entity_a.angular_velocity, a_to_point);
                b_angular_velocity := cross(entity_b.angular_velocity, b_to_point);

                a_inv_mass := 1.0 / entity_a.physics_properties.mass;
                b_inv_mass := 1.0 / entity_b.physics_properties.mass;

                velocity_a := entity_a.velocity + a_angular_velocity;
                velocity_b := entity_b.velocity + b_angular_velocity;

                // todo: elasticity - is this right?
                assert(entity_a.physics_properties.elasticity >= 0 && entity_a.physics_properties.elasticity <= 1);
                assert(entity_b.physics_properties.elasticity >= 0 && entity_b.physics_properties.elasticity <= 1);
                restitution_pt1 := (entity_a.physics_properties.elasticity - entity_b.physics_properties.elasticity);
                restitution_pt2 := (entity_a.physics_properties.elasticity + entity_b.physics_properties.elasticity) * 0.5;
                // restitution := (restitution_pt1 + restitution_pt2) * 0.5;
                restitution := restitution_pt2;

                if entity_b.physics_properties.mass == IMMOVABLE_ENTITY_MASS {
                    speed_along_normal := min(dot(entity_a.velocity, contact_result.normal), 0);
                    normal_impulse_magnitude := speed_along_normal * (1 + restitution);

                    tangent_velocity := velocity_a + speed_along_normal * contact_result.normal;
                    tangent_speed_sq := length_squared(tangent_velocity);
                    tangent_speed: float;
                    if tangent_speed_sq > VERY_SMALL_NUMBER {
                        tangent_speed = sqrt(tangent_speed_sq);
                        pair.contact_tangent = tangent_velocity / tangent_speed;
                    } else {
                        pair.contact_tangent = .{};
                    }
                    friction_impulse_magnitude := tangent_speed;

                    friction_coef := 0.3;
                    friction_impulse := -pair.contact_tangent * (friction_impulse_magnitude * friction_coef);
                    normal_impulse := -contact_result.normal * normal_impulse_magnitude;
                    // total_impulse := normal_impulse + friction_impulse;
                    total_impulse := normal_impulse * COLLISION_IMPULSE_DAMPING;

                    entity_a.velocity += total_impulse; 
                    // if is_set(*entity_a.flags, .PHYSICS_DRIVEN_ROTATION) {
                    //     entity_a.angular_velocity += entity_a.inv_inertia_tensor * cross(a_to_point, total_impulse);
                    // }
                } else {
                    effective_mass: float;
                    if entity_a.shape.type == .SPHERE && entity_b.shape.type == .SPHERE {
                        effective_mass = 1.0 / (a_inv_mass + b_inv_mass);
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

                    entity_a.velocity += total_impulse * a_inv_mass;
                    entity_b.velocity -= total_impulse * b_inv_mass;

                    if is_set(*entity_a.flags, .PHYSICS_DRIVEN_ROTATION) {
                        entity_a.angular_velocity += entity_a.inv_inertia_tensor * cross(a_to_point, total_impulse);
                    }
                    if is_set(*entity_b.flags, .PHYSICS_DRIVEN_ROTATION) {
                        entity_b.angular_velocity += entity_b.inv_inertia_tensor * cross(b_to_point, total_impulse);
                    }
                }
            }
        }
    }
}

solve_contact_positions :: () {
    using context.world;
    for 0..COLLISION_POSITION_ITERATION_COUNT-1 {
        for pair : contact_pairs {
            entity_a := get_entity(pair.a);
            entity_b := get_entity(pair.b);

            contact_result: Contact_Result;
            if solve_potential_contact(entity_a.body, entity_a.axes, entity_b.body, entity_b.axes, PHYSICS_FIXED_TIME_STEP, *contact_result) {
                if entity_b.physics_properties.mass == IMMOVABLE_ENTITY_MASS {
                    force := clamp(COLLISION_POSITION_CORRECTION_DAMPING * (contact_result.depth - COLLISION_OVERLAP_TOLERANCE), 0, COLLISION_MAX_CORRECTION);
                    impulse := contact_result.normal * force;
                    entity_a.center += impulse;
                } else {
                    force := clamp(COLLISION_POSITION_CORRECTION_DAMPING * (contact_result.depth - COLLISION_OVERLAP_TOLERANCE), 0, COLLISION_MAX_CORRECTION);
                    impulse := contact_result.normal * force;
                    inv_mass_sum := 1 / (entity_a.physics_properties.mass + entity_b.physics_properties.mass);
                    impulse_a :=  impulse * ((1.0 / entity_a.physics_properties.mass) * inv_mass_sum);
                    impulse_b := -impulse * ((1.0 / entity_b.physics_properties.mass) * inv_mass_sum);
                    entity_a.center += impulse_a;
                    entity_b.center += impulse_b;
                }
            }
        }
    }
}

warm_start_contacts :: () {
    using context.world;
    for *pair : contact_pairs {
        entity_a := try_get_entity(*pair.a);
        entity_b := try_get_entity(*pair.b);
        if entity_a == null || entity_b == null {
            continue;
        }
        if entity_b.physics_properties.mass == IMMOVABLE_ENTITY_MASS {
            normal_impulse := pair.contact_normal * (pair.normal_impulse_sum * COLLISION_IMPULSE_DAMPING);
            entity_a.velocity += normal_impulse;
        } else {
            normal_impulse := pair.contact_normal * (pair.normal_impulse_sum * COLLISION_IMPULSE_DAMPING);
            entity_a.velocity += normal_impulse * (1.0 / entity_a.physics_properties.mass);
            entity_b.velocity -= normal_impulse * (1.0 / entity_b.physics_properties.mass);
        }
        // todo: warm start angular
    }
}

solve_potential_contact :: (body_a: Physics_Body, axes_a: Axes, body_b: Physics_Body, axes_b: Axes, time_step: float, out_result: *Contact_Result) -> bool {
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

solve_potential_contact_sphere_sphere :: (body_a: Physics_Body, axes_a: Axes, body_b: Physics_Body, axes_b: Axes, time_step: float, out_result: *Contact_Result) -> bool {
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

solve_potential_contact_sphere_rect :: (body_a: Physics_Body, axes_a: Axes, body_b: Physics_Body, axes_b: Axes, time_step: float, out_result: *Contact_Result) -> bool {
    sphere_a    := *body_a.shape.sphere;
    rect_b      := *body_b.shape.rect;

    center_diff := body_a.center - body_b.center;
    distance_along_normal := dot(center_diff, axes_b.fore);
    if distance_along_normal < VERY_SMALL_NUMBER {
        if !rect_b.bidirectional_collision {
            return false;
        }
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

get_aabb :: inline (body: *Physics_Body, axes: Axes) -> AABB {
    out_aabb : AABB = ---;
    out_aabb.center = body.center;
    out_aabb.extent = get_aabb_extent(body.shape, axes.fore, axes.up, axes.right);
    return out_aabb;
}

get_aabb :: inline (entity: *Entity) -> AABB {
    out_aabb : AABB = ---;
    out_aabb.center = entity.center;
    out_aabb.extent = get_aabb_extent(entity.shape, entity.axes.fore, entity.axes.up, entity.axes.right);
    return out_aabb;
}

COLLISION_GRID_ALLOCATOR_MIN_SIZE :: 32;
