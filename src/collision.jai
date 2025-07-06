// this game wants collisions with torque application!
// to do that requires contact point estimation in the collision solving

IMMOVABLE_ENTITY_MASS :: 100_000.0;

potential_collisions: [..]Potential_Collision;

Potential_Collision :: struct {
    entity_a: u16;
    entity_b: u16;
}
// NOTE: colliders should just be always upright. serves the needs of the game and I know it in and out.

Capsule_Collider :: struct {
    half_height: float;
    radius: float;
}

Box_Collider :: struct {
    half_height: float;
    width: float;
    length: float;
}

Plane_Collider :: struct {
    half_height: float;
    width: float; @private
}

Sphere_Collider :: struct {
    radius: float;
}

Entity_Collider :: struct {
    type: enum u32 {
        SPHERE;
        CAPSULE;
        PLANE;
        BOX;
    };
    using data: union {
        half_height: float;
        sphere: Sphere_Collider = ---;
        capsule: Capsule_Collider = ---;
        plane: Plane_Collider = ---;
        box: Box_Collider = ---;
    };
}

min_dimension :: (c: *Entity_Collider) -> float {
    if c.type == {
    case .SPHERE;
        return c.sphere.radius;
    case .CAPSULE;
        return c.capsule.radius;
    case .PLANE;
        return min(c.plane.half_height, c.plane.width * 0.5);
    case .BOX;
        return min(max(c.box.half_height, c.box.width*0.5), c.box.length*0.5);
    }
    return 0.0;
}

// to_bottom_position :: inline (using c: *Entity_Collider, center: Vector3) -> Vector3 {
//     return center - Vector3.{z=height*0.5};
// }

to_collider_center :: inline (using c: *Entity_Collider, bottom_center: Vector3) -> Vector3 {
    return .{xy=bottom_center.xy, z=bottom_center.z + c.half_height};
}

populate_potential_contacts :: () {
    auto_release_temp();

    last_entity := find_last_set_bit(*entities.in_use);
    entity_count := last_entity + 1;

    // todo: grid

    for 0..entity_count-1 {
        phys := *entity_physics_core[it];
        props := get_entity_physics_properties(xx it);
    }
    
    for i : 0..last_entity-1 {
        assert(bit_is_set(*entities.in_use, i));
        if entities[i].type != .STATIC_MESH then continue;
        for j : i+1..last_entity {
            assert(bit_is_set(*entities.in_use, j));
            if entities[j].type != .STATIC_MESH then continue;
            array_add(*potential_collisions, .{xx i, xx j});
        }
    }
}

solve_potential_contacts :: () {
    last_entity := find_last_set_bit(*entities.in_use);
    COLLISION_SOLVE_ITERATION_COUNT :: 1;
    INV_COLLISION_SOLVE_ITERATION_COUNT :: 1.0 / COLLISION_SOLVE_ITERATION_COUNT.(float);
    FIXED_TIME_STEP :: 1.0 / 60.0;
    for 0..last_entity {
        e_phys := *entity_physics_core[it];
        e_phys.flags = 0;
        precalculated_fore_directions[it] = fore_direction(*e_phys.orientation);
        precalculated_up_directions[it] = up_direction(*e_phys.orientation);
    }

    // continuous collision detection - based physics solving

    for solve_iteration : 0..COLLISION_SOLVE_ITERATION_COUNT-1 {
        for entity_index : 0..last_entity {
            if entities[entity_index].id == camera.id then continue;

            e_props := get_entity_physics_properties(xx entity_index);
            if e_props.mass >= IMMOVABLE_ENTITY_MASS then continue;
            if e_props.body_collision_channels == 0 then continue;

            e_phys := *entity_physics_core[entity_index];
            if solve_iteration == 0 {
                e_phys.linear_velocity.z -= e_props.gravity_accel * FIXED_TIME_STEP;
            }

            if entity_index == player_character.index {
                a := 0;
            }
            prev_contacted_entity_index := -1;

            max_step_count := 8;
            remaining_time := FIXED_TIME_STEP * INV_COLLISION_SOLVE_ITERATION_COUNT;
            for 0..max_step_count-1 {
                sweep_beg := e_phys.position;
                sweep_end := sweep_beg + e_phys.linear_velocity * remaining_time;

                closest_contact_norm_time := 1.0;
                closest_contact_point: Vector3;
                closest_contact_normal: Vector3; // toward A
                closest_phys_b: *Entity_Physics_Core;
                closest_props_b: *Physics_Properties;
                closest_entity_index: s64;

                fore_a := *precalculated_fore_directions[entity_index];
                up_a := *precalculated_up_directions[entity_index];

                // todo: grid
                for 0..last_entity {
                    if it == entity_index then continue;
                    if entities[it].id == camera.id then continue;
                    if it == prev_contacted_entity_index then continue;

                    props_b := get_entity_physics_properties(xx it);
                    if (props_b.body_collision_channels & e_props.body_collision_channels) == 0 then continue;

                    phys_b := *entity_physics_core[it];

                    center_b := phys_b.position;
                    fore_b := *precalculated_fore_directions[it];
                    up_b := *precalculated_up_directions[it];

                    contact_norm_time := FLOAT32_MAX;
                    contact_point: Vector3 = ---;
                    contact_normal: Vector3 = ---;

                    is_contact := solve_potential_collision(*sweep_beg, *sweep_end, fore_a, up_a, e_props, *center_b, fore_b, up_b, props_b, *contact_norm_time, *contact_point, *contact_normal);

                    if is_contact && contact_norm_time < closest_contact_norm_time {
                        closest_contact_norm_time = contact_norm_time;
                        closest_contact_point = contact_point;
                        closest_contact_normal = contact_normal;
                        closest_phys_b = phys_b;
                        closest_props_b = props_b;
                        closest_entity_index = it;
                    }
                }

                if closest_contact_norm_time >= 1.0 {
                    e_phys.position = sweep_end;
                    break;
                }
                prev_contacted_entity_index = closest_entity_index;

                // resolve the collision by moving the entity to the contact point (which might mean moving backwards)

                travel_time := closest_contact_norm_time * remaining_time;
                // e_phys.position = closest_contact_point;

                // resolve the physics interaction
                
                if closest_props_b.mass >= IMMOVABLE_ENTITY_MASS {
                    speed_in_direction_of_hit_normal := dot(e_phys.linear_velocity, closest_contact_normal);
                    if speed_in_direction_of_hit_normal < 0.0 {
                        e_phys.linear_velocity -= closest_contact_normal * speed_in_direction_of_hit_normal;
                    }
                    if dot(closest_contact_normal, WORLD_UP) >= COS_PI_OVER_3 {
                        e_phys.flags |= .ON_GROUND;
                    }
                } else {
                    // (0,0) -> 0; (1,1) -> 0; (1,0)-> 1; (0,1) -> 1
                    bounciness := collision_bounciness(e_props, closest_props_b);
                }

                if travel_time == 0 {
                    e_phys.position = closest_contact_point;
                } else {
                    e_phys.position += e_phys.linear_velocity * travel_time;
                }

                // solving for *this* entity in iterations, we may have time time remaining in the step
                // travel time might be negative if we're already colliding
                remaining_time -= max(travel_time, 0);
                if remaining_time <= 0 then break;
            }

            if solve_iteration == COLLISION_SOLVE_ITERATION_COUNT - 1 && (e_phys.flags & .ON_GROUND) != 0 {
                linear_speed_xy_sq := length_squared(e_phys.linear_velocity.xy);
                if linear_speed_xy_sq > 0 {
                    linear_speed_xy := sqrt(linear_speed_xy_sq);
                    velocity_direction_xy := e_phys.linear_velocity.xy * (1.0 / linear_speed_xy);

                    // todo: material friction
                    ground_friction := 1.5;
                    friction_coef := ground_friction * e_props.friction_multiplier + e_props.friction_bias;
                    assert(friction_coef >= 0.0);
                    friction_accel := friction_coef * 98.0;
                    friction_delta := friction_accel * FIXED_TIME_STEP;

                    if friction_delta > linear_speed_xy {
                        e_phys.linear_velocity.xy = .{};
                    } else {
                        e_phys.linear_velocity.xy -= velocity_direction_xy * friction_delta;
                    }
                }
            }
        }
    }

    // ITER_COUNT :: 3;
    // ITER_SOFTENING :: 1.0 / ITER_COUNT.(float);
    // inv_delta_time := 1.0 / delta_time;
    // for 0..ITER_COUNT-1 {
    //     for potential_collisions {
    //         phys_a := *entity_physics_core[it.entity_a];
    //         phys_b := *entity_physics_core[it.entity_b];
    //         props_a := get_entity_physics_properties(it.entity_a);
    //         props_b := get_entity_physics_properties(it.entity_b);
    //         // todo: precalculated forward directions

    //         correction: float;
    //         contact_point: Vector3;
    //         contact_normal: Vector3; // toward A

    //         fore_a := *precalculated_fore_directions[it.entity_a];
    //         up_a := *precalculated_up_directions[it.entity_a];
    //         fore_b := *precalculated_fore_directions[it.entity_b];
    //         up_b := *precalculated_up_directions[it.entity_b];

    //         is_collision := solve_potential_collision(*phys_a.position, *phys_a.linear_velocity, fore_a, up_a, props_a, *phys_b.position, *phys_b.linear_velocity, fore_b, up_b, props_b, *correction, *contact_point, *contact_normal);

    //         if is_collision {
    //             phys_a.linear_velocity -= contact_normal * correction;
                // SOFTENING_FACTOR :: 0.995 * (1.0 / 3.0);
                // inv delta time applied because collision resolution is applying a position delta through velocity
                // a_mass_multiplier, b_mass_multiplier: float = ---;
                // a_softening_factor, b_softening_factor: float = ---;

                // a_min_dim := min_dimension(*props_a.body_collider);
                // b_min_dim := min_dimension(*props_b.body_collider);
                // base_impulse_magnitude := (-collis_gap) * inv_delta_time * ITER_SOFTENING;
                // base_impulse := collis_vec * base_impulse_magnitude;

                // if props_a.mass >= IMMOVABLE_ENTITY_MASS {
                //     if props_b.mass >= IMMOVABLE_ENTITY_MASS {
                //         continue;
                //     }
                //     a_mass_multiplier = 0.0;
                //     b_mass_multiplier = 1.0;
                //     a_softening_factor = 0.0;
                //     b_softening_factor = respace(clamp(-collis_gap / b_min_dim, 0.0, 1.0), .{0, 1}, .{0.0001, 1});
                //     // b_softening_factor = 1.0;
                // } else if props_b.mass >= IMMOVABLE_ENTITY_MASS {
                //     a_mass_multiplier = 1.0;
                //     b_mass_multiplier = 0.0;
                //     a_softening_factor = respace(clamp(-collis_gap / a_min_dim, 0.0, 1.0), .{0, 1}, .{0.0001, 1});
                //     // a_softening_factor = 1.0;
                //     b_softening_factor = 0.0;
                // } else {
                //     inv_mass_sum := 1.0 / (props_a.mass + props_b.mass);
                //     a_mass_multiplier = inv_mass_sum * props_b.mass;
                //     b_mass_multiplier = inv_mass_sum * props_b.mass;
                //     a_softening_factor = clamp(-collis_gap / a_min_dim, 0.0, 1.0);
                //     b_softening_factor = clamp(-collis_gap / b_min_dim, 0.0, 1.0);
                // }

                // a_impulse_magnitude := base_impulse_magnitude * a_mass_multiplier * a_softening_factor;
                // b_impulse_magnitude := base_impulse_magnitude * b_mass_multiplier * b_softening_factor;
                // impulse_a := base_impulse * a_impulse_magnitude;
                // impulse_b := base_impulse * b_impulse_magnitude;

                // apply_velocity_change_with_bounce(*phys_a.linear_velocity, collis_vec, impulse_a, props_a.bounciness);
                // apply_velocity_change_with_bounce(*phys_b.linear_velocity, -collis_vec, -impulse_b, props_b.bounciness);
    //         }
    //     }
    // }
    array_reset_keeping_memory(*potential_collisions);
}

apply_velocity_change_with_bounce :: (linear_velocity: *Vector3, collis_vec: Vector3, impulse: Vector3, bounciness: float) {
    speed_along_impulse_before := dot(collis_vec, linear_velocity.*);
    linear_velocity.* += impulse;
    speed_along_impulse_after := dot(collis_vec, linear_velocity.*);

    speed_along_impulse_delta := speed_along_impulse_after - speed_along_impulse_before;
    if speed_along_impulse_delta > 100.0 {
        a := 0;
    }
    if speed_along_impulse_delta > 0 /*&& speed_along_impulse_before > 0*/ {
        // when moving slow, this will be near zero
        // norm_speed_sq := clamp(speed_along_impulse_delta / (1.0*1.0), 0.0, 1.0);
        // bounce_factor := norm_speed_sq * (1.0 - bounciness);
        // linear_velocity.* -= collis_vec * (speed_along_impulse_delta * (1.0-bounciness));
    }
}

solve_potential_collision :: (position_a_start: *Vector3, position_a_end: *Vector3, forward_a: *Vector3, up_a: *Vector3, properties_a: *Physics_Properties, position_b: *Vector3, forward_b: *Vector3, up_b: *Vector3, properties_b: *Physics_Properties, out_contact_time: *float, out_contact_point: *Vector3, out_contact_normal: *Vector3) -> bool {
    collider_a := *properties_a.body_collider;
    collider_b := *properties_b.body_collider;
    if collider_a.type == .SPHERE && collider_b.type == .PLANE {
        return solve_collision_sphere_plane(position_a_start, position_a_end, forward_a, up_a, properties_a, position_b, forward_b, up_b, properties_b, out_contact_time, out_contact_point, out_contact_normal);
    }
    return false;
}

solve_collision_sphere_plane :: (start_a: *Vector3, end_a: *Vector3, forward_a: *Vector3, up_a: *Vector3, properties_a: *Physics_Properties, position_b: *Vector3, forward_b: *Vector3, up_b: *Vector3, properties_b: *Physics_Properties, out_contact_time: *float, out_contact_point: *Vector3, out_contact_normal: *Vector3) -> bool {
    out_contact_time.* = FLOAT32_MAX;

    sphere_a := *properties_a.body_collider.sphere;
    plane_b := *properties_b.body_collider.plane;

    pos_a_beg := start_a.* + up_a.* * sphere_a.radius;
    pos_a_end := end_a.* + up_a.* * sphere_a.radius;  
    pos_b     := position_b.* + up_b.* * plane_b.half_height;

    toward_a := pos_a_beg - pos_b;
    cos_t := dot(toward_a, forward_b.*);
    if cos_t < 0 {
        // ignore collisions starting behind the plane
        return false;
    }

    a_proj      := project_point_onto_plane(pos_a_beg, pos_b, forward_b.*);
    a_proj_next := project_point_onto_plane(pos_a_end, pos_b, forward_b.*);
    
    // get the plane-relative up and right components of the differences from b center to the capsule segment's projections onto the plane. clamp the projection of a's points onto b's rectangle.

    right_b := cross(forward_b.*, up_b.*);
    assert(is_normalized(right_b, SMALL_NUMBER));

    b_to_a_proj         := a_proj       - pos_b;
    b_to_a_proj_next    := a_proj_next  - pos_b;

    a_proj_up_component_clamped := min(dot(b_to_a_proj, up_b.*), plane_b.half_height);
    a_proj_right_component_clamped := min(dot(b_to_a_proj, right_b), plane_b.width*0.5);

    a_proj_next_up_component_clamped := min(dot(b_to_a_proj_next, up_b.*), plane_b.half_height);
    a_proj_next_right_component_clamped := min(dot(b_to_a_proj_next, right_b), plane_b.width*0.5);

    // this is both points of a's shadow on b's plane, but clamped to b's rectangle.

    a_projected_and_clamped := pos_b + up_b.* * a_proj_up_component_clamped + right_b * a_proj_right_component_clamped;
    a_next_projected_and_clamped := pos_b + up_b.* * a_proj_next_up_component_clamped + right_b * a_proj_next_right_component_clamped;

    a_closest_point, b_closest_point: Vector3 = ---;
    dist_sq := distance_squared_between_line_segments(*pos_a_beg, *pos_a_end, *a_projected_and_clamped, *a_next_projected_and_clamped, *a_closest_point, *b_closest_point);

    out_contact_point.* = b_closest_point;
    out_contact_normal.* = forward_b.*;
    contact_dist: float;

    if dist_sq <= VERY_SMALL_NUMBER {
        // sphere wants to pass through the plane
        // out_contact_normal.* = forward_b.*;

    } else {
        // sphere *may* be penetrating the plane, but not passing through it
        contact_dist = sqrt(dist_sq);
        // could be on plane edge. if two plane redcts are edge-to-edge, you don't really want to use the plane normal, because a corner will push in two directions
        // out_contact_normal.* = (a_closest_point - b_closest_point) / contact_dist;
    }

    out_contact_time.* = dot((out_contact_point.* - start_a.*), (end_a.* - start_a.*)) / contact_dist;

    // return out_position_correction.* > 0;
    return contact_dist < sphere_a.radius;
}
/*
solve_potential_collision :: inline (entity_a: *Entity, entity_b: *Entity) -> bool {
    unused_dir: Vector3 = ---;
    unused_gap: float = ---;
    return solve_potential_collision(entity_a, entity_b, *unused_dir, *unused_gap);
}

solve_potential_collision :: inline (entity_a: *Entity, entity_b: *Entity, out_collision_dir: *Vector3, out_gap: *float) -> bool {
    return solve_potential_collision(*entity_a.position, *entity_a.linear_velocity, *precalculated_fore_directions[entity_a.index], *precalculated_up_directions[entity_a.index], entity_a.physics_properties, *entity_b.position, *entity_b.linear_velocity, *precalculated_fore_directions[entity_b.index], *precalculated_up_directions[entity_b.index], entity_b.physics_properties, out_collision_dir, out_gap);
}

 solve_potential_collision :: (position_a: *Vector3, velocity_a: *Vector3, forward_a: *Vector3, up_a: *Vector3, properties_a: *Physics_Properties, position_b: *Vector3, velocity_b: *Vector3, forward_b: *Vector3, up_b: *Vector3, properties_b: *Physics_Properties, out_collision_dir: *Vector3, out_gap: *float) -> bool {
    collider_a := *properties_a.body_collider;
    collider_b := *properties_b.body_collider;
    if #complete collider_a.type == {
    case .SPHERE;
        if #complete collider_b.type == {
        case .SPHERE;
            return solve_collision_sphere_sphere(position_a, velocity_a, forward_a, up_a, properties_a, position_b, velocity_b, forward_b, up_b, properties_b, out_collision_dir, out_gap);
        case .CAPSULE;
        case .PLANE;
            return solve_collision_sphere_plane(position_a, velocity_a, forward_a, up_a, properties_a, position_b, velocity_b, forward_b, up_b, properties_b, out_collision_dir, out_gap);
        case .BOX;
        }
    case .CAPSULE;
        if #complete collider_b.type == {
        case .SPHERE;
        case .CAPSULE;
            return solve_collision_capsule_capsule(position_a, velocity_a, forward_a, up_a, properties_a, position_b, velocity_b, forward_b, up_b, properties_b, out_collision_dir, out_gap);
        case .PLANE;
            return solve_collision_capsule_plane(position_a, velocity_a, forward_a, up_a, properties_a, position_b, velocity_b, forward_b, up_b, properties_b, out_collision_dir, out_gap);
        case .BOX;
        }
    case .BOX;
        if #complete collider_b.type == {
        case .SPHERE;
        case .CAPSULE;
        case .PLANE;
        case .BOX;
            // return solve_collision_box_box(position_a, velocity_a, forward_a, up_a, properties_a, position_b, velocity_b, forward_b, up_b, properties_b, out_collision_dir, out_gap);
        }
    case .PLANE;
        if #complete collider_b.type == {
        case .SPHERE;
            return solve_collision_plane_sphere(position_a, velocity_a, forward_a, up_a, properties_a, position_b, velocity_b, forward_b, up_b, properties_b, out_collision_dir, out_gap);
        case .CAPSULE;
            return solve_collision_plane_capsule(position_a, velocity_a, forward_a, up_a, properties_a, position_b, velocity_b, forward_b, up_b, properties_b, out_collision_dir, out_gap);
        case .PLANE;
        case .BOX;
        }
    }
    return false;
}

solve_collision_sphere_sphere :: (position_a: *Vector3, velocity_a: *Vector3, forward_a: *Vector3, up_a: *Vector3, properties_a: *Physics_Properties, position_b: *Vector3, velocity_b: *Vector3, forward_b: *Vector3, up_b: *Vector3, properties_b: *Physics_Properties, out_collision_dir: *Vector3, out_gap: *float) -> bool {
    sphere_a := *properties_a.body_collider.sphere;
    sphere_b := *properties_b.body_collider.sphere;

    a_pos_next := position_a.* + velocity_a.* * delta_time;
    b_pos_next := position_b.* + velocity_b.* * delta_time;

    a_closest_point, b_closest_point: Vector3 = ---;
    dist_sq := distance_squared_between_line_segments(position_a, *a_pos_next, position_b, *b_pos_next, *a_closest_point, *b_closest_point);

    buffer_distance := sphere_a.radius + sphere_b.radius;

    if dist_sq < VERY_SMALL_NUMBER {
        out_gap.* = -buffer_distance;
        out_collision_dir.* = .{x=1}; // pick any direction...
    } else {
        dist := sqrt(dist_sq);
        out_gap.* = dist - buffer_distance;
        out_collision_dir.* = (a_closest_point - b_closest_point) * (1.0 / dist); 
    }

    return out_gap.* < 0;   
}

solve_collision_sphere_plane :: (position_a: *Vector3, velocity_a: *Vector3, forward_a: *Vector3, up_a: *Vector3, properties_a: *Physics_Properties, position_b: *Vector3, velocity_b: *Vector3, forward_b: *Vector3, up_b: *Vector3, properties_b: *Physics_Properties, out_collision_dir: *Vector3, out_gap: *float) -> bool {
    sphere_a := *properties_a.body_collider.sphere;
    plane_b := *properties_b.body_collider.plane;

    toward_a := position_a.* - position_b.*;
    cos_t := dot(toward_a, forward_b.*);
    if cos_t < 0 {
        // ignore collisions starting behind the plane
        return false;
    }

    a_pos_next := position_a.* + velocity_a.* * delta_time;
    b_pos_next := position_b.* + velocity_b.* * delta_time;

    a_proj      := project_point_onto_plane(position_a.*, position_b.*, forward_b.*);
    a_proj_next := project_point_onto_plane(a_pos_next, b_pos_next, forward_b.*);
    
    // get the plane-relative up and right components of the differences from b center to the capsule segment's projections onto the plane. clamp the projection of a's points onto b's rectangle.

    right_b := cross(forward_b.*, up_b.*);
    assert(is_normalized(right_b, SMALL_NUMBER));

    b_to_a_proj         := a_proj       - position_b.*;
    b_to_a_proj_next    := a_proj_next  - b_pos_next;

    a_proj_up_component_clamped := min(dot(b_to_a_proj, up_b.*), plane_b.half_height*2.0);
    a_proj_right_component_clamped := min(dot(b_to_a_proj, right_b), plane_b.width);

    a_proj_next_up_component_clamped := min(dot(b_to_a_proj_next, up_b.*), plane_b.half_height*2.0);
    a_proj_next_right_component_clamped := min(dot(b_to_a_proj_next, right_b), plane_b.width);

    // this is both points of a's shadow on b's plane, but clamped to b's rectangle.

    a_projected_and_clamped := position_b.* + up_b.* * a_proj_up_component_clamped + right_b * a_proj_right_component_clamped;
    a_next_projected_and_clamped := b_pos_next + up_b.* * a_proj_next_up_component_clamped + right_b * a_proj_next_right_component_clamped;

    a_closest_point, b_closest_point: Vector3 = ---;
    dist_sq := distance_squared_between_line_segments(position_a, *a_pos_next, *a_projected_and_clamped, *a_next_projected_and_clamped, *a_closest_point, *b_closest_point);

    if dist_sq < VERY_SMALL_NUMBER {
        // since we ignore collisions starting behind the plane, an intersection with the plane must mean the sphere intends to move through the plane this think.
        target_position := b_closest_point + forward_b.* * sphere_a.radius;
        diff := a_pos_next - target_position;
        out_gap.* = dot(diff, forward_b.*);
        out_collision_dir.* = forward_b.*;
    } else {
        dist := sqrt(dist_sq);
        out_gap.* = dist - (sphere_a.radius + dot(velocity_a.*, -forward_b.*));
        out_collision_dir.* = (a_closest_point - b_closest_point) * (1.0 / dist); 
    }

    return out_gap.* < 0;
}

solve_collision_plane_sphere :: (position_a: *Vector3, velocity_a: *Vector3, forward_a: *Vector3, up_a: *Vector3, properties_a: *Physics_Properties, position_b: *Vector3, velocity_b: *Vector3, forward_b: *Vector3, up_b: *Vector3, properties_b: *Physics_Properties, out_collision_dir: *Vector3, out_gap: *float) -> bool {
    is_overlap := solve_collision_sphere_plane(position_b, velocity_b, forward_b, up_b, properties_b, position_a, velocity_a, forward_a, up_a, properties_a, out_collision_dir, out_gap);
    out_collision_dir.* *= -1.0;
    return is_overlap;
}

solve_collision_capsule_capsule :: (position_a: *Vector3, velocity_a: *Vector3, forward_a: *Vector3, up_a: *Vector3, properties_a: *Physics_Properties, position_b: *Vector3, velocity_b: *Vector3, forward_b: *Vector3, up_b: *Vector3, properties_b: *Physics_Properties, out_collision_dir: *Vector3, out_gap: *float) -> bool {
    capsule_a := *properties_a.body_collider.capsule;
    capsule_b := *properties_b.body_collider.capsule;

    a_pos_next := position_a.* + velocity_a.* * delta_time;
    b_pos_next := position_b.* + velocity_b.* * delta_time;

    a_bot := a_pos_next;
    a_bot.z = a_bot.z + capsule_a.radius;
    a_top := a_pos_next;
    a_top.z = a_top.z + (capsule_a.half_height*2.0 - capsule_a.radius);

    b_bot := b_pos_next;
    b_bot.z = b_bot.z + capsule_b.radius;
    b_top := b_pos_next;
    b_top.z = b_top.z + (capsule_b.half_height*2.0 - capsule_b.radius);

    a_closest_point, b_closest_point: Vector3 = ---;
    dist_sq := distance_squared_between_line_segments(*a_bot, *a_top, *b_bot, *b_top, *a_closest_point, *b_closest_point);

    if is_nan_is_inf(dist_sq) || dist_sq < VERY_SMALL_NUMBER {
        return false;
    }

    dist := sqrt(dist_sq);
    buffer_distance := capsule_a.radius + capsule_b.radius;
    out_gap.* = dist - buffer_distance;
    out_collision_dir.* = (a_closest_point - b_closest_point) * (1.0 / dist); 

    return out_gap.* < 0;
}

// solve_collision_box_box :: #insert collision_solver_proc; {

//     return false;
// }

// todo: this assumes b remains fixed
// solve_collision_capsule_plane :: (position_a: *Vector3, velocity_a: *Vector3, forward_a: *Vector3, up_a: *Vector3, properties_a: *Physics_Properties, position_b: *Vector3, velocity_b: *Vector3, forward_b: *Vector3, up_b: *Vector3, properties_b: *Physics_Properties, out_collision_dir: *Vector3, out_gap: *float) -> bool {
//     capsule_a := *properties_a.body_collider.capsule;
//     plane_b := *properties_b.body_collider.plane;

//     ACCEPTABLE_ERROR :: 0.001;


// }

// todo: this assumes b remains fixed
solve_collision_capsule_plane :: (position_a: *Vector3, velocity_a: *Vector3, forward_a: *Vector3, up_a: *Vector3, properties_a: *Physics_Properties, position_b: *Vector3, velocity_b: *Vector3, forward_b: *Vector3, up_b: *Vector3, properties_b: *Physics_Properties, out_collision_dir: *Vector3, out_gap: *float) -> bool {
    capsule_a := *properties_a.body_collider.capsule;
    plane_b := *properties_b.body_collider.plane;

    a_bot := position_a.* + up_a.* * capsule_a.radius;
    a_top := position_a.* + up_a.* * (capsule_a.half_height*2.0 - capsule_a.radius);

    // get a's shadow on the infinite plane that b's rectangle is on

    a_projected_bot_on_plane := project_point_onto_plane(a_bot, position_b.*, forward_b.*);
    a_projected_top_on_plane := project_point_onto_plane(a_top, position_b.*, forward_b.*);
    
    // get the plane-relative up and right components of the differences from b center to the capsule segment's projections onto the plane. clamp the projection of a's points onto b's rectangle.

    right_b := cross(forward_b.*, up_b.*);
    assert(is_normalized(right_b, SMALL_NUMBER));

    b_to_a_proj_bot := a_projected_bot_on_plane - position_a.*;
    b_to_a_proj_top := a_projected_top_on_plane - position_b.*;

    a_proj_bot_up_component_clamped := min(dot(b_to_a_proj_bot, up_b.*), plane_b.half_height*2.0);
    a_proj_bot_right_component_clamped := min(dot(b_to_a_proj_bot, right_b), plane_b.width);

    a_proj_top_up_component_clamped := min(dot(b_to_a_proj_top, up_b.*), plane_b.half_height*2.0);
    a_proj_top_right_component_clamped := min(dot(b_to_a_proj_top, right_b), plane_b.width);

    // this is both points of a's shadow on b's plane, but clamped to b's rectangle.

    a_bot_projected_and_clamped := position_b.* + up_b.* * a_proj_bot_up_component_clamped + right_b * a_proj_bot_right_component_clamped;
    a_top_projected_and_clamped := position_b.* + up_b.* * a_proj_top_up_component_clamped + right_b * a_proj_top_right_component_clamped;

    // the clamped shadow of a's line segment can be used much like another capsule collider's line segment. we want to know the closest point on each line segment here.

    a_closest_point, b_closest_point: Vector3 = ---;
    dist_sq := distance_squared_between_line_segments(*a_bot, *a_top, *a_bot_projected_and_clamped, *a_top_projected_and_clamped, *a_closest_point, *b_closest_point);

    a_pos_next := position_a.* + velocity_a.* * delta_time;
    b_pos_next := position_b.* + velocity_b.* * delta_time;

    a_bot_next := a_pos_next + up_a.* * capsule_a.radius;
    a_top_next := a_pos_next + up_a.* * (capsule_a.half_height*2.0 - capsule_a.radius);

    a_closest_point_next, b_closest_point_next: Vector3 = ---;
    dist_sq_next := distance_squared_between_line_segments(*a_bot_next, *a_top_next, *a_bot_projected_and_clamped, *a_top_projected_and_clamped, *a_closest_point_next, *b_closest_point_next);

    if is_nan_is_inf(dist_sq) || is_nan_is_inf(dist_sq_next) {
        return false;
    }

    toward_a := a_closest_point - b_closest_point;
    toward_a_next := a_closest_point_next - b_closest_point_next;

    // cur dist along plane normal
    cos_theta   := dot(forward_b.*, toward_a); 
    // next dist along neg plane normal
    cos_phi     := dot(forward_b.*, toward_a_next); 
    cos_phi = ifx cos_theta > 0 && cos_phi < 0 then -cos_phi else 0;

    dist := ifx dist_sq <= VERY_SMALL_NUMBER then 0.0 else sqrt(dist_sq);
    dist_next := ifx dist_sq_next <= VERY_SMALL_NUMBER then 0.0 else sqrt(dist_sq_next);

    buffer_dist := capsule_a.radius;
    out_gap.* = cos_theta - (cos_phi + buffer_dist);
    out_collision_dir.* = forward_b.*;

    return out_gap.* < 0;
}

solve_collision_plane_capsule :: (position_a: *Vector3, velocity_a: *Vector3, forward_a: *Vector3, up_a: *Vector3, properties_a: *Physics_Properties, position_b: *Vector3, velocity_b: *Vector3, forward_b: *Vector3, up_b: *Vector3, properties_b: *Physics_Properties, out_collision_dir: *Vector3, out_gap: *float) -> bool  {
    is_overlap := solve_collision_capsule_plane(position_b, velocity_b, forward_b, up_b, properties_b, position_a, velocity_a, forward_a, up_a, properties_a, out_collision_dir, out_gap);
    out_collision_dir.* *= -1.0;
    return is_overlap;
}

*/