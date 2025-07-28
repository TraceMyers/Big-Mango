// this game wants collisions with torque application!
// to do that requires contact point estimation in the collision solving

RUN_PHYSICS_DEBUGGER :: false;
COLLISION_SOLVE_ITERATION_COUNT :: 1;
INV_COLLISION_SOLVE_ITERATION_COUNT :: 1.0 / COLLISION_SOLVE_ITERATION_COUNT.(float);
FIXED_TIME_STEP :: 1.0 / 400.0;

Collision_Intermediate_Data :: struct {
    type: enum {
        SPHERE_SPHERE::1;
        SPHERE_RECT;
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

    solve: struct {
        type: enum { ONE_WAY; TWO_WAY; };
        _bounciness: float;
        using which: union {
            one_way: struct {
                _speed_in_direction_of_hit_normal: float;
                _full_bounce_speed: float;
                _bounce_impulse: Vector3;
            } = ---;
            two_way: struct {
                _relative_velocity: Vector3;
                _rv_along_normal: float;
                _self_impulse: Vector3;
                _other_impulse: Vector3;
                _impulse_magnitude: float;
                _base_impulse: Vector3;
                _new_normal_speed: float;
                _self_normal_momentum: float;
                _other_normal_momentum: float;
                _inv_mass_sum: float;
            } = ---;
        }
    }

    using specific: union {
        sphere_sphere: struct {
            _point_on_segment: Vector3;
            _point_on_line: Vector3;
            _segment_dist: float;
            _line_dist: float;
            _move_back_from_line_proj_dist: float;
            _a_radius_portion: float;
        } = ---;
        sphere_rect: struct {
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

#if RUN_PHYSICS_DEBUGGER {
    physics_debug_global_data := struct{
        collision_entity_index := 1;
        collision_entity_id := 0;
        inner_index_1 := 0;
        remaining_time := FIXED_TIME_STEP * INV_COLLISION_SOLVE_ITERATION_COUNT;
        prev_contacted_entity_index := -1;
        prev_contacted_entity_id := -1;
        e_props: *Physics_Properties;
        e_phys: *Entity_Physics_Core;
        closest_collision_result: Collision_Result;
        closest_phys_b: *Entity_Physics_Core;
        closest_props_b: *Physics_Properties;
        closest_entity_index: s64;
        closest_entity_id: s64;
        fucking_fuck: [..]s16;
    }.{};
} else {
    physics_debug_global_data: struct{};
}

#if RUN_PHYSICS_DEBUGGER {
    collision_intermediate: Collision_Intermediate_Data;
    physics_debugger_pause := false;
    physics_debugger_step := false;
    do_phys_debugger_turnover := false;
}

physics_debugger_entity_ids: [..]u32;
physics_debugger_ignore_immovable := false;

queue_phys_debugger_entity_turnover :: inline () {
    #if RUN_PHYSICS_DEBUGGER {
        if physics_debugger_pause then do_phys_debugger_turnover = true;
    }
}

phys_debugger_entity_turnover :: () #expand {
    using physics_debug_global_data;
    inner_index_1 = 0;
    collision_entity_index += 1;

    remaining_time = FIXED_TIME_STEP * INV_COLLISION_SOLVE_ITERATION_COUNT;
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

    if collision_entity_index == `last_entity + 1 {
        collision_entity_index = 1;
    }
}

phys_debugger_outer_loop_continue :: () #expand {
    using physics_debug_global_data;
    if physics_debugger_pause {
        collision_entity_index = increment_wrap(collision_entity_index, 1, `last_entity);
        return;
    } {
        collision_entity_index += 1;
        continue;
    }
}

prep_ccd_substeps :: () #expand {
    using physics_debug_global_data;
    `remaining_time = FIXED_TIME_STEP * INV_COLLISION_SOLVE_ITERATION_COUNT;
    `prev_contacted_entity_index = -1;
    array_reset_keeping_memory(*`fucking_fuck);
}

test_ref: Entity_Ref;

solve_physics :: () {
    using physics_debug_global_data;
    auto_release_temp();

    last_entity := entities.count-1;

    #if RUN_PHYSICS_DEBUGGER {
        if physics_debugger_pause {
            if !physics_debugger_step {
                return;
            }
            physics_debugger_step = false;
            if do_phys_debugger_turnover {
                phys_debugger_entity_turnover();
                do_phys_debugger_turnover = false;
            }
        } else {
            collision_entity_index = 1;
            inner_index_1 = 0;
            remaining_time = FIXED_TIME_STEP * INV_COLLISION_SOLVE_ITERATION_COUNT;
            prev_contacted_entity_index = -1;
        }
    } else {
        collision_entity_index := 1;
        inner_index_1 := 0;
        remaining_time := FIXED_TIME_STEP * INV_COLLISION_SOLVE_ITERATION_COUNT;
        prev_contacted_entity_index := -1;
        e_props: *Physics_Properties;
        e_phys: *Entity_Physics_Core;
        closest_collision_result: Collision_Result;
        closest_phys_b: *Entity_Physics_Core;
        closest_props_b: *Physics_Properties;
        closest_entity_index: s64;
        fucking_fuck: [..]s16;
        fucking_fuck.allocator = temp;
    }

    for 0..last_entity {
        e_phys := *entity_physics_core[it];
        // todo: persistent flag set
        e_phys.physics_flags &= ~ENTITY_PHYSICS_PER_FRAME_FLAGS;
        precalculated_fore_directions[it] = fore_direction(*e_phys.orientation);
        precalculated_up_directions[it] = up_direction(*e_phys.orientation);
    }

    // continuous collision detection - based physics solving

    max_step_count := 8;
    solve_iteration := 0;

    // for solve_iteration : 0..COLLISION_SOLVE_ITERATION_COUNT-1 {
    {
        while collision_entity_index <= last_entity {
            #if !RUN_PHYSICS_DEBUGGER then defer collision_entity_index += 1;

            if collision_entity_index == INVALID_ENTITY_INDEX {
                #if RUN_PHYSICS_DEBUGGER {
                    phys_debugger_outer_loop_continue();
                } else continue;
            }
            if entities[collision_entity_index].type == .CAMERA {
                #if RUN_PHYSICS_DEBUGGER {
                    phys_debugger_outer_loop_continue();
                } else continue;
            }

            e_props = get_physics_properties_at(collision_entity_index);
            if e_props.mass <= IMMOVABLE_ENTITY_MASS {
                #if RUN_PHYSICS_DEBUGGER {
                    phys_debugger_outer_loop_continue();
                } else continue;
            }
            if e_props.body_collision_channels == 0 {
                #if RUN_PHYSICS_DEBUGGER {
                    phys_debugger_outer_loop_continue();
                } else continue;
            }

            // apply gravity

            e_phys = *entity_physics_core[collision_entity_index];
            if solve_iteration == 0 {
                e_phys.linear_velocity.z -= e_props.gravity_accel * FIXED_TIME_STEP;
            }

            #if !RUN_PHYSICS_DEBUGGER {
                prep_ccd_substeps();
            } else {
                if !physics_debugger_pause {
                    prep_ccd_substeps();
                }
            }
            
            if test_ref.index == collision_entity_index {
                a := 0;
            }

            while inner_index_1 < max_step_count {
                inner_index_1 += 1;

                sweep_beg := e_phys.position;
                sweep_end := sweep_beg + e_phys.linear_velocity * remaining_time;

                fore_a := precalculated_fore_directions[collision_entity_index];
                up_a := precalculated_up_directions[collision_entity_index];

                closest_collision_result = .{contact_norm_time=1.0};
                closest_phys_b = null;
                closest_props_b = null;
                closest_entity_index = -1;

                #if RUN_PHYSICS_DEBUGGER {
                    closest_collision_intermediate: Collision_Intermediate_Data = ---;
                    closest_entity_id = -1;
                }

                inner_index_2 := 1;
                while inner_index_2 <= last_entity {
                    defer inner_index_2 += 1;

                    if inner_index_2 == collision_entity_index then continue;
                    if inner_index_2 == prev_contacted_entity_index then continue;
                    props_b := get_physics_properties_at(inner_index_2);
                    if (props_b.body_collision_channels & e_props.body_collision_channels) == 0 then continue;
                    if array_find(fucking_fuck, inner_index_2.(s16)) then continue;

                    phys_b := *entity_physics_core[inner_index_2];

                    center_b := phys_b.position;
                    fore_b := precalculated_fore_directions[inner_index_2];
                    up_b := precalculated_up_directions[inner_index_2];

                    collision_result: Collision_Result;
                    is_contact := solve_potential_collision(sweep_beg, sweep_end, fore_a, up_a, e_props, center_b, fore_b, up_b, props_b, *collision_result);

                    if is_contact {
                        contact_is_closer := collision_result.contact_norm_time < closest_collision_result.contact_norm_time;
                        replace_closest := contact_is_closer;
                        if !replace_closest {
                            contact_is_immovable := props_b.mass <= IMMOVABLE_ENTITY_MASS;
                            closest_is_immovable := closest_props_b.mass <= IMMOVABLE_ENTITY_MASS;
                            replace_closest = contact_is_immovable && !closest_is_immovable;
                        }

                        if replace_closest {
                            closest_collision_result = collision_result;
                            closest_phys_b = phys_b;
                            closest_props_b = props_b;
                            closest_entity_index = inner_index_2;
                            #if RUN_PHYSICS_DEBUGGER {
                                closest_collision_intermediate = collision_intermediate;
                                closest_entity_id = entities[inner_index_2].id;
                            }
                        }
                    }
                }

                #if RUN_PHYSICS_DEBUGGER {
                    physics_debugger_pause = false;
                }

                array_add(*fucking_fuck, xx closest_entity_index);
                prev_contacted_entity_index = closest_entity_index;

                using closest_collision_result;

                if contact_norm_time >= 1.0 {
                    e_phys.position = sweep_end;
                    queue_phys_debugger_entity_turnover();
                    break;
                }

                #if RUN_PHYSICS_DEBUGGER {
                    if !physics_debugger_ignore_immovable || closest_props_b.mass > IMMOVABLE_ENTITY_MASS {
                        physics_debugger_pause = array_find(physics_debugger_entity_ids, xx closest_entity_id) || array_find(physics_debugger_entity_ids, entities[collision_entity_index].id);
                        if physics_debugger_pause {
                            collision_intermediate = closest_collision_intermediate;
                        }
                    } else {
                        physics_debugger_pause = false;
                    }
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

                if closest_props_b.mass == IMMOVABLE_ENTITY_MASS {
                    full_bounce_speed := reflection_component(e_phys.linear_velocity, contact_normal) * 0.5;
                    // kill all velocity along normal because the other thing can't move
                    speed_in_direction_of_hit_normal := dot(e_phys.linear_velocity, contact_normal);
                    if speed_in_direction_of_hit_normal < 0.0 {
                        e_phys.linear_velocity -= contact_normal * speed_in_direction_of_hit_normal;
                    }
                    if dot(contact_normal, WORLD_UP) >= COS_PI_OVER_3 {
                        e_phys.physics_flags |= .ON_GROUND;
                    }

                    // multiply by 0.5 because this vector would be added to the velocity in order to perfectly bounce. but, half of this is already dealt with in the part where we kill the velocity's component along the collision normal
                    bounce_impulse := contact_normal * (bounciness * full_bounce_speed);
                    e_phys.linear_velocity += bounce_impulse;
                    #if RUN_PHYSICS_DEBUGGER {
                        if physics_debugger_pause {
                            using collision_intermediate.solve;
                            type = .ONE_WAY;
                            _bounciness = bounciness;
                            one_way._speed_in_direction_of_hit_normal = speed_in_direction_of_hit_normal;
                            one_way._full_bounce_speed = full_bounce_speed;
                            one_way._bounce_impulse = bounce_impulse;
                        }
                    }
                } else {
                    relative_velocity := closest_phys_b.linear_velocity - e_phys.linear_velocity;
                    rv_along_normal := dot(relative_velocity, contact_normal);
                    if rv_along_normal > 0 {
                        inv_mass_a, inv_mass_b, impulse_magnitude: float = ---;
                        base_impulse, self_impulse, other_impulse: Vector3 = ---;
                        if bounciness > 0 {
                            inv_mass_a = 1.0 / e_props.mass;
                            inv_mass_b = 1.0 / closest_props_b.mass;
                            impulse_magnitude = -(1.0 + bounciness) * rv_along_normal / (inv_mass_a + inv_mass_b);
                            base_impulse = contact_normal * impulse_magnitude;
                            self_impulse = -base_impulse * closest_props_b.mass;
                            other_impulse = base_impulse * e_props.mass;
                        } else {

                            inv_mass_sum := 1.0 / (e_props.mass + closest_props_b.mass);

                            self_speed_along_normal := dot(e_phys.linear_velocity, contact_normal);
                            other_speed_along_normal := dot(closest_phys_b.linear_velocity, contact_normal);

                            self_normal_momentum := e_props.mass * -self_speed_along_normal;
                            other_normal_momentum := closest_props_b.mass * other_speed_along_normal;

                            new_normal_speed := (self_normal_momentum - other_normal_momentum) * inv_mass_sum;

                            self_impulse = -contact_normal * (new_normal_speed + self_speed_along_normal); 
                            other_impulse = -contact_normal * (new_normal_speed + other_speed_along_normal);

                            #if RUN_PHYSICS_DEBUGGER {
                                if physics_debugger_pause {
                                    using collision_intermediate.solve;
                                    inv_mass_a, inv_mass_b = 0;
                                    two_way._new_normal_speed = new_normal_speed;
                                    two_way._self_normal_momentum = self_normal_momentum;
                                    two_way._other_normal_momentum = other_normal_momentum;
                                    two_way._inv_mass_sum = inv_mass_sum;
                                }
                            }
                        }

                        e_phys.linear_velocity += self_impulse;
                        closest_phys_b.linear_velocity += other_impulse;

                        #if RUN_PHYSICS_DEBUGGER {
                            if physics_debugger_pause {
                                using collision_intermediate.solve;
                                type = .TWO_WAY;
                                two_way._relative_velocity = relative_velocity;
                                two_way._rv_along_normal = rv_along_normal;
                                two_way._self_impulse = self_impulse;
                                two_way._other_impulse = other_impulse;
                                two_way._impulse_magnitude = impulse_magnitude;
                                two_way._base_impulse = base_impulse;
                            }
                        }
                    } else {
                        #if RUN_PHYSICS_DEBUGGER {
                            if physics_debugger_pause {
                                using collision_intermediate.solve;
                                type = .TWO_WAY;
                                two_way._relative_velocity = relative_velocity;
                                two_way._rv_along_normal = rv_along_normal;
                                two_way._self_impulse = .{};
                                two_way._other_impulse = .{};
                                two_way._impulse_magnitude = 0;
                                two_way._base_impulse = .{};
                            }
                        }
                    }
                }

                // solving for *this* entity in iterations, we may have time time remaining in the step. travel time might be negative if we're already colliding
                remaining_time -= max(travel_time, 0);
                if remaining_time <= 0 {
                    queue_phys_debugger_entity_turnover();
                    break;
                }
                #if RUN_PHYSICS_DEBUGGER {
                    if physics_debugger_pause {
                        if inner_index_1 == max_step_count {
                            queue_phys_debugger_entity_turnover();
                        }
                        break;
                    }
                }
            }

            if solve_iteration == COLLISION_SOLVE_ITERATION_COUNT - 1 {
                // friction
                if (e_phys.physics_flags & .ON_GROUND) != 0 {
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
                
                // linear move
                if e_phys.linear_input.xy != .{} {
                    prev_speed_sq := length_squared(e_phys.linear_velocity.xy);
                    linear_accel := e_props.linear_acceleration;

                    if prev_speed_sq > SMALL_NUMBER {
                        prev_speed := sqrt(prev_speed_sq);
                        prev_velocity_dir := e_phys.linear_velocity.xy / prev_speed;
                        cos_t := dot(e_phys.linear_input.xy, prev_velocity_dir);
                        if cos_t <= COS_PI_OVER_4 {
                            linear_accel *= e_props.accel_opposite_direction_multiplier;
                        }
                    }
                    if prev_speed_sq <= e_props.fast_start_speed_max {
                        linear_accel *= 4.0;
                    }

                    e_phys.linear_velocity.xy += e_phys.linear_input.xy * (linear_accel * FIXED_TIME_STEP);
                    new_speed_sq := length_squared(e_phys.linear_velocity.xy);

                    if new_speed_sq > square(e_props.linear_speed_max) {
                        new_speed := sqrt(new_speed_sq);
                        e_phys.linear_velocity.xy *= e_props.linear_speed_max / new_speed;
                    }

                    // commented out because it doesn't gel with first person
                    // rotate
                    // rot_speed := 6.5 * PI;
                    // axis := normalize(WORLD_UP + WORLD_RIGHT);
                    // target := make_quat(e_phys.linear_input, WORLD_UP);
                    // interp_rotate(*e_phys.orientation, target, rot_speed, FIXED_TIME_STEP);

                    e_phys.linear_input = .{};
                }

                // jump
                if (e_phys.physics_flags & .JUMP_QUEUED) != 0 {
                    if (e_phys.physics_flags & .ON_GROUND) != 0 {
                        do_jump := true;
                        #if !RUN_PHYSICS_DEBUGGER {
                            time_since_queued := seconds_since_init().(float) - e_phys.jump_queued_at_time;
                            if time_since_queued > delta_time {
                                do_jump = false;
                            }
                        }
                        if do_jump {
                            e_phys.linear_velocity.z += e_props.jump_delta_velocity;
                        }
                    }
                    e_phys.physics_flags &= ~.JUMP_QUEUED;
                    e_phys.jump_queued_at_time = -999.0;
                }
            }
            #if RUN_PHYSICS_DEBUGGER {
                if physics_debugger_pause then return;
                else collision_entity_index += 1;
            }
        }
    }
}

solve_potential_collision :: inline (position_a_start: Vector3, position_a_end: Vector3, forward_a: Vector3, up_a: Vector3, properties_a: *Physics_Properties, position_b: Vector3, forward_b: Vector3, up_b: Vector3, properties_b: *Physics_Properties, result: *Collision_Result) -> bool {
    #if RUN_PHYSICS_DEBUGGER {
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
        case .RECT;
            return solve_collision_sphere_rect(position_a_start, position_a_end, forward_a, up_a, properties_a, position_b, forward_b, up_b, properties_b, result);
        case .BOX;
        case .AABB;
        case .HALF_SPACE;
        }
    case .CAPSULE;
        if collider_b.type == {
        case .SPHERE;
        case .CAPSULE;
        case .RECT;
        case .BOX;
        case .AABB;
        case .HALF_SPACE;
        }
    case .RECT;
        if collider_b.type == {
        case .SPHERE;
        case .CAPSULE;
        case .RECT;
        case .BOX;
        case .AABB;
        case .HALF_SPACE;
        }
    case .BOX;
        if collider_b.type == {
        case .SPHERE;
        case .CAPSULE;
        case .RECT;
        case .BOX;
        case .AABB;
        case .HALF_SPACE;
        }
    case .AABB;
        if collider_b.type == {
        case .SPHERE;
        case .CAPSULE;
        case .RECT;
        case .BOX;
        case .AABB;
        case .HALF_SPACE;
        }
    case .HALF_SPACE;
        if collider_b.type == {
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

solve_collision_sphere_rect :: (pos_a_beg: Vector3, pos_a_end: Vector3, forward_a: Vector3, up_a: Vector3, properties_a: *Physics_Properties, pos_b: Vector3, forward_b: Vector3, up_b: Vector3, properties_b: *Physics_Properties, result: *Collision_Result) -> bool {
    #if RUN_PHYSICS_DEBUGGER {
        collision_intermediate.type = .SPHERE_RECT;
    }
    result.contact_norm_time = FLOAT32_MAX;
    sphere_a := *properties_a.body_collider.sphere;
    rect_b := *properties_b.body_collider.rect;

    toward_a := pos_a_beg - pos_b;
    cos_t := dot(toward_a, forward_b);
    if cos_t < 0 {
        // ignore collisions starting behind the rect
        return false;
    }

    a_proj      := project_point_onto_plane(pos_a_beg, pos_b, forward_b);
    a_proj_next := project_point_onto_plane(pos_a_end, pos_b, forward_b);
    
    // get the plane-relative up and right components of the differences from b center to the capsule segment's projections onto the plane. clamp the projection of a's points onto b's rectangle.

    right_b := cross(forward_b, up_b);
    assert(is_normalized(right_b, SMALLISH_NUMBER));

    b_to_a_proj         := a_proj       - pos_b;
    b_to_a_proj_next    := a_proj_next  - pos_b;

    a_proj_up_component_clamped := clamp(dot(b_to_a_proj, up_b), -rect_b.half_height, rect_b.half_height);
    a_proj_right_component_clamped := clamp(dot(b_to_a_proj, right_b), -rect_b.half_width, rect_b.half_width);

    a_proj_next_up_component_clamped := clamp(dot(b_to_a_proj_next, up_b), -rect_b.half_height, rect_b.half_height);
    a_proj_next_right_component_clamped := clamp(dot(b_to_a_proj_next, right_b), -rect_b.half_width, rect_b.half_width);

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
        #if RUN_PHYSICS_DEBUGGER {
            using collision_intermediate.specific.sphere_rect;
            _full_travel_dist = full_travel_dist;
            _travel_norm = travel_norm;
            _cos_t = cos_t;
        }
        if abs(cos_t) <= VERY_SMALL_NUMBER {
            result.contact_norm_time = 0;
        } else {
            assert(cos_t > 0);
            // heading toward rect
            signed_distance_to_collis := result.contact_depth / cos_t;
            result.contact_norm_time = signed_distance_to_collis / full_travel_dist;
        }
    }

    #if RUN_PHYSICS_DEBUGGER {
        using collision_intermediate.specific.sphere_rect;
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

    result.is_contact = result.contact_depth > 0 && result.contact_norm_time < 1;
    return result.is_contact;
}

solve_collision_sphere_sphere :: (pos_a_beg: Vector3, pos_a_end: Vector3, forward_a: Vector3, up_a: Vector3, properties_a: *Physics_Properties, pos_b: Vector3, forward_b: Vector3, up_b: Vector3, properties_b: *Physics_Properties, result: *Collision_Result) -> bool {
    #if RUN_PHYSICS_DEBUGGER {
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
    }

    result.is_contact = true;
    result.do_move = true;

    #if RUN_PHYSICS_DEBUGGER {
        using collision_intermediate.specific.sphere_sphere;
        _point_on_segment = pt_on_segment;
        _point_on_line = pt_on_line;
        _segment_dist = seg_dist;
        _line_dist = sqrt(line_dist_sq);
        _move_back_from_line_proj_dist = move_back_from_line_proj_dist;
        _a_radius_portion = a_radius_portion;
    }

    return result.contact_norm_time < 1;
}
