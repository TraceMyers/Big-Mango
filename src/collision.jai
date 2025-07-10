// this game wants collisions with torque application!
// to do that requires contact point estimation in the collision solving

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
    width: float;
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

Collision_Result :: struct {
    contact_norm_time: float;
    contact_depth: float;
    contact_point: Vector3;
    contact_normal: Vector3;
    is_contact: bool;
    do_move: bool;
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
    // auto_release_temp();

    // last_entity := find_last_set_bit(*entities.in_use);
    // entity_count := last_entity + 1;

    // // todo: grid

    // for 0..entity_count-1 {
    //     phys := *entity_physics_core[it];
    //     props := get_entity_physics_properties(xx it);
    // }
    
    // for i : 0..last_entity-1 {
    //     assert(bit_is_set(*entities.in_use, i));
    //     if entities[i].type != .STATIC_MESH then continue;
    //     for j : i+1..last_entity {
    //         assert(bit_is_set(*entities.in_use, j));
    //         if entities[j].type != .STATIC_MESH then continue;
    //         array_add(*potential_collisions, .{xx i, xx j});
    //     }
    // }
}

Collision_Intermediate_Data :: struct {
    type: enum {
        SPHERE_SPHERE::1;
        SPHERE_PLANE;
    };

    using basic: struct {
        _pos_a_begin: Vector3;
        _pos_a_end: Vector3;
        _pos_b: Vector3;
        _up_a: Vector3;
        _up_b: Vector3;
        _forward_a: Vector3;
        _forward_b: Vector3;
    };

    using specific: union {
        sphere_sphere: struct {
            _point_on_segment: Vector3;
            _point_on_line: Vector3;
            _segment_dist: float;
            _line_dist: float;
            _move_back_from_line_proj_dist: float;
            _a_radius_portion: float;
        } = ---;
        sphere_plane: struct {
            _a_proj: Vector3;
            _a_proj_next: Vector3;
            _right_b: Vector3;
            _b_to_a_proj: Vector3;
            _b_to_a_proj_next: Vector3;
            _a_projected_and_clamped: Vector3;
            _a_next_projected_and_clamped: Vector3;
            _a_closest_point: Vector3;
            _b_closest_point: Vector3;
            _dist_sq: float;
            _full_travel_dist: float;
            _travel_norm: Vector3;
            _cos_t: float;
            _c: float;
            _truncated_dist: float;
        } = ---;
    };
}

COLLISION_SOLVE_ITERATION_COUNT :: 1;
INV_COLLISION_SOLVE_ITERATION_COUNT :: 1.0 / COLLISION_SOLVE_ITERATION_COUNT.(float);
FIXED_TIME_STEP :: 1.0 / 60.0;

entity_index := 1;
inner_index_1 := 0;
remaining_time := FIXED_TIME_STEP * INV_COLLISION_SOLVE_ITERATION_COUNT;

fucking_fuck: [..]s16;
prev_contacted_entity_index := -1;

e_props: *Physics_Properties;
e_phys: *Entity_Physics_Core;
closest_collision_result: Collision_Result;
closest_phys_b: *Entity_Physics_Core;
closest_props_b: *Physics_Properties;
closest_entity_index: s64;
collision_intermediate: Collision_Intermediate_Data;

physics_debugger_step := false;
do_phys_debugger_turnover := false;

queue_phys_debugger_entity_turnover :: () {
    do_phys_debugger_turnover = true;
}

phys_debugger_entity_turnover :: () #expand {
    remaining_time = FIXED_TIME_STEP * INV_COLLISION_SOLVE_ITERATION_COUNT;
    inner_index_1 = 0;
    entity_index += 1;
    array_reset_keeping_memory(*fucking_fuck);
    prev_contacted_entity_index = -1;

    closest_collision_result = .{};
    closest_collision_result.contact_norm_time = 1.0;
    closest_phys_b = null;
    closest_props_b = null;
    closest_entity_index = -1;

    e_props = null;
    e_phys = null;

    collision_intermediate = .{};

    if entity_index == `last_entity + 1 {
        entity_index = 1;
    }
}

solve_potential_contacts :: () {

    if !physics_debugger_step {
        return;
    }
    physics_debugger_step = false;

    last_entity := find_last_set_bit(*entities.in_use);

    if do_phys_debugger_turnover {
        phys_debugger_entity_turnover();
        do_phys_debugger_turnover = false;
    }

    for 0..last_entity {
        e_phys := *entity_physics_core[it];
        e_phys.flags = 0;
        precalculated_fore_directions[it] = fore_direction(*e_phys.orientation);
        precalculated_up_directions[it] = up_direction(*e_phys.orientation);
    }

    // continuous collision detection - based physics solving

    max_step_count := 8;
    solve_iteration := 0;

    // for solve_iteration : 0..COLLISION_SOLVE_ITERATION_COUNT-1 {
    {
        while entity_index <= last_entity {
            if entity_index == INVALID_ENTITY_INDEX {
                entity_index = increment_wrap(entity_index, 1, last_entity);
                return;
            }

            if entities[entity_index].id == camera.id {
                entity_index = increment_wrap(entity_index, 1, last_entity);
                return;
            }

            e_props = get_entity_physics_properties(xx entity_index);
            if e_props.mass <= IMMOVABLE_ENTITY_MASS {
                entity_index = increment_wrap(entity_index, 1, last_entity);
                return;
            }
            if e_props.body_collision_channels == 0 {
                entity_index = increment_wrap(entity_index, 1, last_entity);
                return;
            }

            // apply gravity

            e_phys = *entity_physics_core[entity_index];
            if solve_iteration == 0 {
                e_phys.linear_velocity.z -= e_props.gravity_accel * FIXED_TIME_STEP;
            }

            while inner_index_1 < max_step_count {

                sweep_beg := e_phys.position;
                sweep_end := sweep_beg + e_phys.linear_velocity * remaining_time;

                fore_a := precalculated_fore_directions[entity_index];
                up_a := precalculated_up_directions[entity_index];

                closest_collision_result = .{};
                closest_collision_result.contact_norm_time = 1.0;

                closest_collision_intermediate: Collision_Intermediate_Data = ---;

                // todo: grid
                inner_index_2 := 1;
                while inner_index_2 <= last_entity {
                    defer inner_index_2 += 1;

                    if inner_index_2 == entity_index then continue;
                    if entities[inner_index_2].id == camera.id then continue;
                    if inner_index_2 == prev_contacted_entity_index then continue;
                    if array_find(fucking_fuck, inner_index_2.(s16)) then continue;

                    props_b := get_entity_physics_properties(xx inner_index_2);
                    if (props_b.body_collision_channels & e_props.body_collision_channels) == 0 then continue;

                    phys_b := *entity_physics_core[inner_index_2];

                    center_b := phys_b.position;
                    fore_b := precalculated_fore_directions[inner_index_2];
                    up_b := precalculated_up_directions[inner_index_2];

                    collision_result: Collision_Result;
                    is_contact := solve_potential_collision(sweep_beg, sweep_end, fore_a, up_a, e_props, center_b, fore_b, up_b, props_b, *collision_result);

                    if is_contact && collision_result.contact_norm_time < closest_collision_result.contact_norm_time {
                        closest_collision_result = collision_result;
                        closest_phys_b = phys_b;
                        closest_props_b = props_b;
                        closest_entity_index = inner_index_2;
                        #if true {
                            closest_collision_intermediate = collision_intermediate;
                        }
                    }
                }

                array_add(*fucking_fuck, xx closest_entity_index);
                prev_contacted_entity_index = closest_entity_index;

                #if true {
                    collision_intermediate = closest_collision_intermediate;
                }

                inner_index_1 += 1;
                if inner_index_1 == max_step_count {
                    queue_phys_debugger_entity_turnover();
                    break;
                }

                using closest_collision_result;

                if contact_norm_time >= 1.0 {
                    e_phys.position = sweep_end;
                    queue_phys_debugger_entity_turnover();
                    break;
                }

                // resolve the collision by moving the entity to the contact point, which might mean moving backwards (negative norm time)

                travel_time := contact_norm_time * remaining_time;
                // not true if we're exactly on the contact surface
                if do_move {
                    if travel_time == 0 {
                        e_phys.position += contact_normal * contact_depth;
                    } else {
                        e_phys.position += e_phys.linear_velocity * travel_time;
                    }
                }

                // resolve the physics interaction

                bounciness := collision_bounciness(e_props, closest_props_b);

                assert(closest_props_b.mass >= 0);

                // todo: immovable entity mass should just be 0
                if closest_props_b.mass == IMMOVABLE_ENTITY_MASS {
                    // kill all velocity along normal because the other thing can't move
                    speed_in_direction_of_hit_normal := dot(e_phys.linear_velocity, contact_normal);
                    if speed_in_direction_of_hit_normal < 0.0 {
                        e_phys.linear_velocity -= contact_normal * speed_in_direction_of_hit_normal;
                    }
                    if dot(contact_normal, WORLD_UP) >= COS_PI_OVER_3 {
                        e_phys.flags |= .ON_GROUND;
                    }

                    // multiply by 0.5 because this vector would be added to the velocity in order to perfectly bounce. but, half of this is already dealt with in the part where we kill the velocity's component along the collision normal
                    full_bounce_speed := reflection_component(e_phys.linear_velocity, contact_normal) * 0.5;
                    e_phys.linear_velocity += contact_normal * (bounciness * full_bounce_speed);
                } else {
                    if e_props.body_collider.type == .SPHERE && closest_props_b.body_collider.type == .SPHERE {
                        a := 0;
                    }
                    relative_velocity := closest_phys_b.linear_velocity - e_phys.linear_velocity;
                    rv_along_normal := dot(relative_velocity, contact_normal);
                    if rv_along_normal > 0 {
                        inv_mass_a := 1.0 / e_props.mass;
                        inv_mass_b := 1.0 / closest_props_b.mass;
                        impulse_magnitude := -(1.0 + bounciness) * rv_along_normal / (inv_mass_a + inv_mass_b);
                        impulse := contact_normal * impulse_magnitude;

                        e_phys.linear_velocity -= impulse * closest_props_b.mass;
                        closest_phys_b.linear_velocity += impulse * e_props.mass;
                    }
                }

                // solving for *this* entity in iterations, we may have time time remaining in the step. travel time might be negative if we're already colliding
                remaining_time -= max(travel_time, 0);
                if remaining_time <= 0 {
                    queue_phys_debugger_entity_turnover();
                }
                break;
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
            return;
        }
    }
}

solve_potential_collision :: inline (position_a_start: Vector3, position_a_end: Vector3, forward_a: Vector3, up_a: Vector3, properties_a: *Physics_Properties, position_b: Vector3, forward_b: Vector3, up_b: Vector3, properties_b: *Physics_Properties, result: *Collision_Result) -> bool {
    #if true {
        using collision_intermediate.basic;
        _pos_a_begin = position_a_start;
        _pos_a_end = position_a_end;
        _pos_b = position_b;
        _up_a = up_a;
        _up_b = up_b;
        _forward_a = forward_a;
        _forward_b = forward_b;
    }
    collider_a := *properties_a.body_collider;
    collider_b := *properties_b.body_collider;
    if collider_a.type == {
    case .SPHERE;
        if collider_b.type == {
        case .SPHERE;
            return solve_collision_sphere_sphere(position_a_start, position_a_end, forward_a, up_a, properties_a, position_b, forward_b, up_b, properties_b, result);
        case .CAPSULE;
        case .PLANE;
            return solve_collision_sphere_plane(position_a_start, position_a_end, forward_a, up_a, properties_a, position_b, forward_b, up_b, properties_b, result);
        case .BOX;
        }
    case .CAPSULE;
        if collider_b.type == {
        case .SPHERE;
        case .CAPSULE;
        case .PLANE;
        case .BOX;
        }
    case .PLANE;
        if collider_b.type == {
        case .SPHERE;
        case .CAPSULE;
        case .PLANE;
        case .BOX;
        }
    case .BOX;
        if collider_b.type == {
        case .SPHERE;
        case .CAPSULE;
        case .PLANE;
        case .BOX;
        }
    }
    return false;
}

solve_collision_sphere_plane :: (pos_a_beg: Vector3, pos_a_end: Vector3, forward_a: Vector3, up_a: Vector3, properties_a: *Physics_Properties, pos_b: Vector3, forward_b: Vector3, up_b: Vector3, properties_b: *Physics_Properties, result: *Collision_Result) -> bool {
    #if true {
        collision_intermediate.type = .SPHERE_PLANE;
    }
    result.contact_norm_time = FLOAT32_MAX;
    sphere_a := *properties_a.body_collider.sphere;
    plane_b := *properties_b.body_collider.plane;

    toward_a := pos_a_beg - pos_b;
    cos_t := dot(toward_a, forward_b);
    if cos_t < 0 {
        // ignore collisions starting behind the plane
        return false;
    }

    a_proj      := project_point_onto_plane(pos_a_beg, pos_b, forward_b);
    a_proj_next := project_point_onto_plane(pos_a_end, pos_b, forward_b);
    
    // get the plane-relative up and right components of the differences from b center to the capsule segment's projections onto the plane. clamp the projection of a's points onto b's rectangle.

    right_b := cross(forward_b, up_b);
    assert(is_normalized(right_b, SMALL_NUMBER));

    b_to_a_proj         := a_proj       - pos_b;
    b_to_a_proj_next    := a_proj_next  - pos_b;

    a_proj_up_component_clamped := clamp(dot(b_to_a_proj, up_b), -plane_b.half_height, plane_b.half_height);
    a_proj_right_component_clamped := clamp(dot(b_to_a_proj, right_b), -plane_b.width*0.5, plane_b.width*0.5);

    a_proj_next_up_component_clamped := clamp(dot(b_to_a_proj_next, up_b), -plane_b.half_height, plane_b.half_height);
    a_proj_next_right_component_clamped := clamp(dot(b_to_a_proj_next, right_b), -plane_b.width*0.5, plane_b.width*0.5);

    // this is both points of a's shadow on b's plane, but clamped to b's rectangle.

    a_projected_and_clamped := pos_b + up_b * a_proj_up_component_clamped + right_b * a_proj_right_component_clamped;
    a_next_projected_and_clamped := pos_b + up_b * a_proj_next_up_component_clamped + right_b * a_proj_next_right_component_clamped;

    a_closest_point, b_closest_point: Vector3 = ---;
    dist_sq := distance_squared_between_line_segments(*pos_a_beg, *pos_a_end, *a_projected_and_clamped, *a_next_projected_and_clamped, *a_closest_point, *b_closest_point);

    result.contact_normal = forward_b;
    result.contact_point = b_closest_point;
    result.do_move = true;

    a_beg_proj_dist_sq := distance_squared(a_projected_and_clamped, pos_a_beg);

    if a_beg_proj_dist_sq < square(sphere_a.radius) {
        result.contact_depth = sphere_a.radius - sqrt(a_beg_proj_dist_sq);
        result.contact_norm_time = 0;
        return true;
    }

    if dist_sq <= VERY_SMALL_NUMBER {
        result.contact_depth = sphere_a.radius;
    } else {
        result.contact_depth = sphere_a.radius - sqrt(dist_sq);
    }

    // todo: faster math below this point

    // todo: don't need ?
    if dist_sq >= square(sphere_a.radius) {
        return false;
    }

    full_travel_dist_sq := distance_squared(pos_a_beg, pos_a_end);
    if full_travel_dist_sq <= VERY_SMALL_NUMBER {
        // not moving
        result.contact_norm_time = 0;
    } else {
        // yes moving
        // todo: simplify this. can probably do with math somehow
        full_travel_dist := sqrt(full_travel_dist_sq);
        travel_norm := (pos_a_end - pos_a_beg) / full_travel_dist;
        cos_t = dot(travel_norm, -result.contact_normal);
        #if true {
            using collision_intermediate.specific.sphere_plane;
            _full_travel_dist = full_travel_dist;
            _travel_norm = travel_norm;
            _cos_t = cos_t;
        }
        if abs(cos_t) <= VERY_SMALL_NUMBER {
            result.contact_norm_time = 0;
        } else {
            assert(cos_t > 0);
            // heading toward plane
            signed_distance_to_collis := result.contact_depth / cos_t;
            result.contact_norm_time = signed_distance_to_collis / full_travel_dist;
            #if true {
                using collision_intermediate.specific.sphere_plane;
                _c = 0;
                _truncated_dist = 0;
            }
        }
    }

    #if true {
        using collision_intermediate.specific.sphere_plane;
        _a_proj = a_proj;
        _a_proj_next = a_proj_next;
        _right_b = right_b;
        _b_to_a_proj = b_to_a_proj;
        _b_to_a_proj_next = b_to_a_proj_next;
        _a_projected_and_clamped = a_projected_and_clamped;
        _a_next_projected_and_clamped = a_next_projected_and_clamped;
        _a_closest_point = a_closest_point;
        _b_closest_point = b_closest_point;
        _dist_sq = dist_sq;
    }

    result.is_contact = result.contact_depth > 0;
    return result.is_contact;
}

solve_collision_sphere_sphere :: (pos_a_beg: Vector3, pos_a_end: Vector3, forward_a: Vector3, up_a: Vector3, properties_a: *Physics_Properties, pos_b: Vector3, forward_b: Vector3, up_b: Vector3, properties_b: *Physics_Properties, result: *Collision_Result) -> bool {
    #if true {
        collision_intermediate.type = .SPHERE_SPHERE;
    }
    result.contact_norm_time = FLOAT32_MAX;
    sphere_a := *properties_a.body_collider.sphere;
    sphere_b := *properties_b.body_collider.sphere;

    pt_on_line, pt_on_segment: Vector3 = ---;
    closest_point_on_line_and_segment(*pos_b, *pos_a_beg, *pos_a_end, *pt_on_line, *pt_on_segment);
    seg_dist_sq := distance_squared(pt_on_segment, pos_b);

    buffer_dist := sphere_a.radius + sphere_b.radius;
    buffer_dist_sq := square(buffer_dist);

    if seg_dist_sq >= buffer_dist_sq {
        result.is_contact = false;
        return false;
    } else if seg_dist_sq <= VERY_SMALL_NUMBER {
        return false;
    }

    line_dist_sq := distance_squared(pt_on_line, pos_b);
    seg_dist := sqrt(seg_dist_sq);
    line_dist := sqrt(line_dist_sq);
    proj_diff := line_dist - seg_dist;
    
    // todo: seg_dist_sq == line_dist_sq
    move_back_from_line_proj_dist := sqrt(buffer_dist_sq - line_dist_sq);

    a_radius_portion := sphere_a.radius / buffer_dist;
    a_dist_sq := distance_squared(pos_a_end, pos_a_beg);

    if a_dist_sq <= VERY_SMALL_NUMBER {
        result.contact_norm_time = 0;
        result.contact_depth = buffer_dist - seg_dist;
        result.contact_point = pos_a_beg + (pos_b - pos_a_beg) * a_radius_portion;
        result.contact_normal = normalize(pos_a_beg - pos_b);
    } else {
        a_dist := sqrt(a_dist_sq);
        a_norm := (pos_a_end - pos_a_beg) / a_dist;
        move_up_to_pt: Vector3;
        if dot(a_norm, pos_b - pt_on_segment) > 0 {
            move_up_to_pt = pt_on_line - a_norm * move_back_from_line_proj_dist;
        } else {
            move_up_to_pt = pt_on_line + a_norm * move_back_from_line_proj_dist;
        }
        norm_time := dot(pos_a_end - pos_a_beg, move_up_to_pt - pos_a_beg) / square(a_dist);
        a_center_at_contact := pos_a_beg + (pos_a_end - pos_a_beg) * norm_time;

        result.contact_norm_time = norm_time;
        result.contact_depth = buffer_dist - seg_dist;
        result.contact_point = a_center_at_contact + (pos_b - a_center_at_contact) * a_radius_portion;
        result.contact_normal = normalize(a_center_at_contact - pos_b);

        if result.contact_norm_time < -50 {
            a := 0;
        }
    }


    result.is_contact = true;
    result.do_move = true;

    #if true {
        using collision_intermediate.specific.sphere_sphere;
        _point_on_segment = pt_on_segment;
        _point_on_line = pt_on_line;
        _segment_dist = seg_dist;
        _line_dist = sqrt(line_dist_sq);
        _move_back_from_line_proj_dist = move_back_from_line_proj_dist;
        _a_radius_portion = a_radius_portion;
    }

    return true;
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