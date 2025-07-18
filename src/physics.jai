// this game wants collisions with torque application!
// to do that requires contact point estimation in the collision solving

RUN_PHYSICS_DEBUGGER :: false;
COLLISION_SOLVE_ITERATION_COUNT :: 1;
INV_COLLISION_SOLVE_ITERATION_COUNT :: 1.0 / COLLISION_SOLVE_ITERATION_COUNT.(float);
FIXED_TIME_STEP :: 1.0 / 400.0;

Capsule_Collider :: struct {
    half_height: float;
    radius: float;
}

Box_Collider :: struct {
    half_height: float;
    half_width: float;
    half_length: float;
#place half_height;
    extent: Vector3 = ---;
}

Plane_Collider :: struct {
    half_height: float;
    half_width: float;
#place half_height;
    extent: Vector2 = ---;
}

Sphere_Collider :: struct {
    radius: float;
}

AABB_Collider :: struct {
    half_height: float;
    half_width: float;
    half_length: float;
#place half_height;
    extent: Vector3 = ---;
}

Entity_Collider :: struct {
    type: enum u32 {
        SPHERE;
        CAPSULE;
        PLANE;
        BOX;
        AABB;
    };
    using data: union {
        half_height: float;
        sphere: Sphere_Collider = ---;
        capsule: Capsule_Collider = ---;
        plane: Plane_Collider = ---;
        box: Box_Collider = ---;
        aabb: AABB_Collider = ---;
    };
}

get_aabb_extent :: (collider: Entity_Collider, orientation: Quaternion) -> Vector3 {
    if #complete collider.type == {
    case .SPHERE;
        using collider.sphere;
        return .{radius, radius, radius};
    case .CAPSULE;
        using collider.capsule;
        axis_up := up_direction(*orientation);
        segment_half_len := half_height - radius;
        segment_point := axis_up * segment_half_len;
        return abs(segment_point) + Vector3.{radius,radius,radius};
    case .PLANE;
        using collider.plane;
        axis_up     := up_direction(*orientation);
        axis_right  := right_direction(*orientation);
        abs_point_1 := abs(axis_up * half_height + axis_right * half_width);
        abs_point_2 := abs(axis_up * half_height - axis_right * half_width);
        return max(abs_point_1, abs_point_2);
    case .BOX;
        using collider.box;
        axis_up, axis_fore, axis_right: Vector3 = ---;    
        get_axes(*orientation, *axis_up, *axis_fore, *axis_right);
        height_vec := abs(axis_up * half_height);
        length_vec := abs(axis_fore * half_length);
        width_vec  := abs(axis_right * half_width);
        return max(height_vec, max(length_vec, width_vec));
    case .AABB;
        using collider.aabb;
        return .{half_width, half_length, half_height};
    }
}

get_bounding_sphere_radius :: (collider: Entity_Collider) -> float {
    if #complete collider.type == {
    case .SPHERE;
        using collider.sphere;
        return radius;
    case .CAPSULE;
        using collider.capsule;
        return half_height; 
    case .PLANE;
        using collider.plane;
        return sqrt(square(half_width) + square(half_height));
    case .BOX;
        using collider.box;
        return sqrt(square(half_width) + square(half_length) + square(half_height));
    case .AABB;
        using collider.aabb;
        return sqrt(square(half_width) + square(half_length) + square(half_height));
    }
}
 

get_aabb :: inline (collider: Entity_Collider, position: Vector3, orientation: Quaternion, out_aabb: *AABB)  {
    out_aabb.center = position;
    out_aabb.extent = get_aabb_extent(collider, orientation);
}


Collision_Result :: struct {
    contact_norm_time: float;
    contact_depth: float;
    contact_point: Vector3;
    contact_normal: Vector3;
    is_contact: bool;
    do_move: bool;
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

            e_props = get_entity_physics_properties_at(collision_entity_index);
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
                    props_b := get_entity_physics_properties_at(inner_index_2);
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
        case .PLANE;
            return solve_collision_sphere_plane(position_a_start, position_a_end, forward_a, up_a, properties_a, position_b, forward_b, up_b, properties_b, result);
        case .BOX;
        case .AABB;
        }
    case .CAPSULE;
        if collider_b.type == {
        case .SPHERE;
        case .CAPSULE;
        case .PLANE;
        case .BOX;
        case .AABB;
        }
    case .PLANE;
        if collider_b.type == {
        case .SPHERE;
        case .CAPSULE;
        case .PLANE;
        case .BOX;
        case .AABB;
        }
    case .BOX;
        if collider_b.type == {
        case .SPHERE;
        case .CAPSULE;
        case .PLANE;
        case .BOX;
        case .AABB;
        }
    case .AABB;
        if collider_b.type == {
        case .SPHERE;
        case .CAPSULE;
        case .PLANE;
        case .BOX;
        case .AABB;
        }
    }
    return false;
}

solve_collision_sphere_plane :: (pos_a_beg: Vector3, pos_a_end: Vector3, forward_a: Vector3, up_a: Vector3, properties_a: *Physics_Properties, pos_b: Vector3, forward_b: Vector3, up_b: Vector3, properties_b: *Physics_Properties, result: *Collision_Result) -> bool {
    #if RUN_PHYSICS_DEBUGGER {
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
    assert(is_normalized(right_b, SMALLISH_NUMBER));

    b_to_a_proj         := a_proj       - pos_b;
    b_to_a_proj_next    := a_proj_next  - pos_b;

    a_proj_up_component_clamped := clamp(dot(b_to_a_proj, up_b), -plane_b.half_height, plane_b.half_height);
    a_proj_right_component_clamped := clamp(dot(b_to_a_proj, right_b), -plane_b.half_width, plane_b.half_width);

    a_proj_next_up_component_clamped := clamp(dot(b_to_a_proj_next, up_b), -plane_b.half_height, plane_b.half_height);
    a_proj_next_right_component_clamped := clamp(dot(b_to_a_proj_next, right_b), -plane_b.half_width, plane_b.half_width);

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
        }
    }

    #if RUN_PHYSICS_DEBUGGER {
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

is_overlap :: (collider_a: Entity_Collider, position_a: Vector3, orientation_a: Quaternion, collider_b: Entity_Collider, position_b: Vector3, orientation_b: Quaternion) -> bool {
    if collider_a.type == {
    case .SPHERE;
        if collider_b.type == {
        case .SPHERE;
            return is_overlap_sphere_sphere(collider_a, position_a, orientation_a, collider_b, position_b, orientation_b);
        case .CAPSULE;
            return is_overlap_sphere_capsule(collider_a, position_a, orientation_a, collider_b, position_b, orientation_b);
        case .PLANE;
            return is_overlap_sphere_plane(collider_a, position_a, orientation_a, collider_b, position_b, orientation_b);
        case .BOX;
            return is_overlap_sphere_box(collider_a, position_a, orientation_a, collider_b, position_b, orientation_b);
        case .AABB;
            return is_overlap_sphere_aabb(collider_a, position_a, orientation_a, collider_b, position_b, orientation_b);
        }
    case .CAPSULE;
        if collider_b.type == {
        case .SPHERE;
            return is_overlap_capsule_sphere(collider_a, position_a, orientation_a, collider_b, position_b, orientation_b);
        case .CAPSULE;
            return is_overlap_capsule_capsule(collider_a, position_a, orientation_a, collider_b, position_b, orientation_b);
        case .PLANE;
            return is_overlap_capsule_plane(collider_a, position_a, orientation_a, collider_b, position_b, orientation_b);
        case .BOX;
            return is_overlap_capsule_box(collider_a, position_a, orientation_a, collider_b, position_b, orientation_b);
        case .AABB;
            return is_overlap_capsule_aabb(collider_a, position_a, orientation_a, collider_b, position_b, orientation_b);
        }
    case .PLANE;
        if collider_b.type == {
        case .SPHERE;
            return is_overlap_plane_sphere(collider_a, position_a, orientation_a, collider_b, position_b, orientation_b);
        case .CAPSULE;
            return is_overlap_plane_capsule(collider_a, position_a, orientation_a, collider_b, position_b, orientation_b);
        case .PLANE;
            return is_overlap_plane_plane(collider_a, position_a, orientation_a, collider_b, position_b, orientation_b);
        case .BOX;
            return is_overlap_plane_box(collider_a, position_a, orientation_a, collider_b, position_b, orientation_b);
        case .AABB;
            return is_overlap_plane_aabb(collider_a, position_a, orientation_a, collider_b, position_b, orientation_b);
        }
    case .BOX;
        if collider_b.type == {
        case .SPHERE;
            return is_overlap_box_sphere(collider_a, position_a, orientation_a, collider_b, position_b, orientation_b);
        case .CAPSULE;
            return is_overlap_box_capsule(collider_a, position_a, orientation_a, collider_b, position_b, orientation_b);
        case .PLANE;
            return is_overlap_box_plane(collider_a, position_a, orientation_a, collider_b, position_b, orientation_b);
        case .BOX;
            return is_overlap_box_box(collider_a, position_a, orientation_a, collider_b, position_b, orientation_b);
        case .AABB;
            return is_overlap_box_aabb(collider_a, position_a, orientation_a, collider_b, position_b, orientation_b);
        }
    case .AABB;
        if collider_b.type == {
        case .SPHERE;
            return is_overlap_aabb_sphere(collider_a, position_a, orientation_a, collider_b, position_b, orientation_b);
        case .CAPSULE;
            return is_overlap_aabb_capsule(collider_a, position_a, orientation_a, collider_b, position_b, orientation_b);
        case .PLANE;
            return is_overlap_aabb_plane(collider_a, position_a, orientation_a, collider_b, position_b, orientation_b);
        case .BOX;
            return is_overlap_aabb_box(collider_a, position_a, orientation_a, collider_b, position_b, orientation_b);
        case .AABB;
            return is_overlap_aabb_aabb(collider_a, position_a, orientation_a, collider_b, position_b, orientation_b);
        }
    }
    return false;
}

// ------------------------------------------------------------------------------------------------------- sphere

is_overlap_sphere_sphere :: (collider_a: Entity_Collider, position_a: Vector3, orientation_a: Quaternion, collider_b: Entity_Collider, position_b: Vector3, orientation_b: Quaternion) -> bool {
    sphere_a := *collider_a.sphere;
    sphere_b := *collider_b.sphere;
    combined_radii := sphere_a.radius + sphere_b.radius;
    return distance_squared(position_a, position_b) < square(combined_radii);
}

is_overlap_sphere_capsule :: (collider_a: Entity_Collider, position_a: Vector3, orientation_a: Quaternion, collider_b: Entity_Collider, position_b: Vector3, orientation_b: Quaternion) -> bool {
    sphere_a    := *collider_a.sphere;
    capsule_b   := *collider_b.capsule;

    capsule_up := up_direction(*orientation_b);
    capsule_seg_pt_0 := position_b + capsule_up * (capsule_b.half_height - capsule_b.radius);
    capsule_seg_pt_1 := position_b - capsule_up * (capsule_b.half_height - capsule_b.radius);

    pt_on_seg := closest_point_on_line_segment(*position_a, *capsule_seg_pt_0, *capsule_seg_pt_1);
    combined_radii := sphere_a.radius + capsule_b.radius;
    return distance_squared(position_a, pt_on_seg) < square(combined_radii);
}

is_overlap_sphere_plane :: (collider_a: Entity_Collider, position_a: Vector3, orientation_a: Quaternion, collider_b: Entity_Collider, position_b: Vector3, orientation_b: Quaternion) -> bool {
    sphere_a    := *collider_a.sphere;
    plane_b     := *collider_b.plane;

    plane_normal, plane_height_vec, plane_width_vec: Vector3 = ---;
    get_axes(orientation_b, *plane_normal, *plane_height_vec, *plane_width_vec);

    pt_on_infinite_plane := project_point_onto_plane(position_a, position_b, plane_normal);

    diff_along_plane := pt_on_infinite_plane - position_b;
    clamped_height_dist := clamp(dot(diff_along_plane, plane_height_vec), -plane_b.half_height, plane_b.half_height);
    clamped_width_dist := clamp(dot(diff_along_plane, plane_width_vec), -plane_b.half_width, plane_b.half_width);

    pt_on_plane := position_b + plane_height_vec * clamped_height_dist + plane_width_vec * clamped_width_dist;

    return distance_squared(position_a, pt_on_plane) < square(sphere_a.radius);
}

is_overlap_sphere_box :: (collider_a: Entity_Collider, position_a: Vector3, orientation_a: Quaternion, collider_b: Entity_Collider, position_b: Vector3, orientation_b: Quaternion) -> bool {
    sphere_a    := *collider_a.sphere;
    box_b       := *collider_b.box;

    box_fore, box_up, box_right: Vector3 = ---;
    get_axes(orientation_b, *box_fore, *box_up, *box_right);

    toward_sphere_diff := position_a - position_b;
    clamped_fore_dist := clamp(dot(toward_sphere_diff, box_fore), -box_b.half_length, box_b.half_length);
    clamped_up_dist := clamp(dot(toward_sphere_diff, box_up), -box_b.half_height, box_b.half_height);
    clamped_right_dist := clamp(dot(toward_sphere_diff, box_right), -box_b.half_width, box_b.half_width);

    pt_in_box := position_b + box_fore * clamped_fore_dist + box_up * clamped_up_dist + box_right * clamped_right_dist;

    return distance_squared(position_a, pt_in_box) < square(sphere_a.radius);
}

is_overlap_sphere_aabb :: (collider_a: Entity_Collider, position_a: Vector3, orientation_a: Quaternion, collider_b: Entity_Collider, position_b: Vector3, orientation_b: Quaternion) -> bool {
    sphere_a    := *collider_a.sphere;
    aabb_b      := *collider_b.aabb;

    toward_sphere_diff := position_a - position_b;
    clamped_fore_dist := clamp(toward_sphere_diff.y, -aabb_b.half_length, aabb_b.half_length);
    clamped_up_dist := clamp(toward_sphere_diff.z, -aabb_b.half_height, aabb_b.half_height);
    clamped_right_dist := clamp(toward_sphere_diff.x, -aabb_b.half_width, aabb_b.half_width);

    pt_in_box := position_b + Vector3.{clamped_right_dist, clamped_fore_dist, clamped_up_dist};

    return distance_squared(position_a, pt_in_box) < square(sphere_a.radius);
}

// ------------------------------------------------------------------------------------------------------- capsule

is_overlap_capsule_sphere :: inline (collider_a: Entity_Collider, position_a: Vector3, orientation_a: Quaternion, collider_b: Entity_Collider, position_b: Vector3, orientation_b: Quaternion) -> bool {
    return is_overlap_sphere_capsule(collider_b, position_b, orientation_b, collider_a, position_a, orientation_a);
}

is_overlap_capsule_capsule :: (collider_a: Entity_Collider, position_a: Vector3, orientation_a: Quaternion, collider_b: Entity_Collider, position_b: Vector3, orientation_b: Quaternion) -> bool {
    capsule_a := *collider_a.capsule;
    capsule_b := *collider_b.capsule;

    a_up := up_direction(*orientation_a);
    a_seg_pt_0 := position_a + a_up * (capsule_a.half_height - capsule_a.radius);
    a_seg_pt_1 := position_a - a_up * (capsule_a.half_height - capsule_a.radius);

    b_up := up_direction(*orientation_b);
    b_seg_pt_0 := position_b + b_up * (capsule_b.half_height - capsule_b.radius);
    b_seg_pt_1 := position_b - b_up * (capsule_b.half_height - capsule_b.radius);

    pt_on_a, pt_on_b: Vector3 = ---;
    closest_point_on_each_line_segment(a_seg_pt_0, a_seg_pt_1, b_seg_pt_0, b_seg_pt_1, *pt_on_a, *pt_on_b);
    combined_radii := capsule_a.radius + capsule_b.radius;

    return distance_squared(pt_on_a, pt_on_b) < square(combined_radii);
}

is_overlap_capsule_plane :: (collider_a: Entity_Collider, position_a: Vector3, orientation_a: Quaternion, collider_b: Entity_Collider, position_b: Vector3, orientation_b: Quaternion) -> bool {
    capsule_a   := *collider_a.capsule;
    plane_b     := *collider_b.plane;

    a_up := up_direction(*orientation_a);
    a_seg_pt_0 := position_a + a_up * (capsule_a.half_height - capsule_a.radius);
    a_seg_pt_1 := position_a - a_up * (capsule_a.half_height - capsule_a.radius);

    plane_normal, plane_height_vec, plane_width_vec: Vector3 = ---;
    get_axes(orientation_b, *plane_normal, *plane_height_vec, *plane_width_vec);

    a_seg_pt_0_projected := project_point_onto_plane(a_seg_pt_0, position_b, plane_normal);
    a_seg_pt_1_projected := project_point_onto_plane(a_seg_pt_1, position_b, plane_normal);

    diff_along_plane_0 := a_seg_pt_0_projected - position_b;
    clamped_height_dist_0 := clamp(dot(diff_along_plane_0, plane_height_vec), -plane_b.half_height, plane_b.half_height);
    clamped_width_dist_0 := clamp(dot(diff_along_plane_0, plane_width_vec), -plane_b.half_width, plane_b.half_width);

    diff_along_plane_1 := a_seg_pt_1_projected - position_b;
    clamped_height_dist_1 := clamp(dot(diff_along_plane_1, plane_height_vec), -plane_b.half_height, plane_b.half_height);
    clamped_width_dist_1 := clamp(dot(diff_along_plane_1, plane_width_vec), -plane_b.half_width, plane_b.half_width);

    a_seg_pt_0_projected_and_clamped := position_b + plane_width_vec * clamped_width_dist_0 + plane_height_vec * clamped_height_dist_0;
    a_seg_pt_1_projected_and_clamped := position_b + plane_width_vec * clamped_width_dist_1 + plane_height_vec * clamped_height_dist_1;

    pt_on_a, pt_on_b: Vector3 = ---;
    closest_point_on_each_line_segment(a_seg_pt_0, a_seg_pt_1, a_seg_pt_0_projected_and_clamped, a_seg_pt_1_projected_and_clamped, *pt_on_a, *pt_on_b);

    return distance_squared(pt_on_a, pt_on_b) < square(capsule_a.radius);
}

is_overlap_capsule_box :: (collider_a: Entity_Collider, position_a: Vector3, orientation_a: Quaternion, collider_b: Entity_Collider, position_b: Vector3, orientation_b: Quaternion) -> bool {
    capsule_a   := *collider_a.capsule;
    box_b       := *collider_b.box;

    b_inverse_rotation := Quaternion.{xyz=-orientation_b.xyz, w=orientation_b.w};
    position_a_box_relative := position_a - position_b;
    position_a_box_space := rotate(position_a_box_relative, b_inverse_rotation);

    orientation_a_box_space := b_inverse_rotation * orientation_a;
    a_up_box_space := up_direction(*orientation_a_box_space);

    a_seg_pt_0 := position_a_box_space + a_up_box_space * (capsule_a.half_height - capsule_a.radius);
    a_seg_pt_1 := position_a_box_space - a_up_box_space * (capsule_a.half_height - capsule_a.radius);

    box_extent := Vector3.{box_b.half_width, box_b.half_length, box_b.half_height};
    pt_on_segment := closest_point_on_line_segment_from_aabb_at_origin(a_seg_pt_0, a_seg_pt_1, box_extent);
    pt_clamped_to_box := clamp(pt_on_segment, box_extent);
    
    return distance_squared(pt_on_segment, pt_clamped_to_box) < square(capsule_a.radius);
}

is_overlap_capsule_aabb :: (collider_a: Entity_Collider, position_a: Vector3, orientation_a: Quaternion, collider_b: Entity_Collider, position_b: Vector3, orientation_b: Quaternion) -> bool {
    capsule_a   := *collider_a.capsule;
    box_b       := *collider_b.box;

    position_a_box_space := position_a - position_b;
    a_up_box_space := up_direction(*orientation_a);

    a_seg_pt_0 := position_a_box_space + a_up_box_space * (capsule_a.half_height - capsule_a.radius);
    a_seg_pt_1 := position_a_box_space - a_up_box_space * (capsule_a.half_height - capsule_a.radius);

    box_extent := Vector3.{box_b.half_width, box_b.half_length, box_b.half_height};
    pt_on_segment := closest_point_on_line_segment_from_aabb_at_origin(a_seg_pt_0, a_seg_pt_1, box_extent);
    pt_clamped_to_box := clamp(pt_on_segment, box_extent);
    
    return distance_squared(pt_on_segment, pt_clamped_to_box) < square(capsule_a.radius);
}

// ------------------------------------------------------------------------------------------------------- plane

is_overlap_plane_sphere :: inline (collider_a: Entity_Collider, position_a: Vector3, orientation_a: Quaternion, collider_b: Entity_Collider, position_b: Vector3, orientation_b: Quaternion) -> bool {
    return is_overlap_sphere_plane(collider_b, position_b, orientation_b, collider_a, position_a, orientation_a);
}

is_overlap_plane_capsule :: inline (collider_a: Entity_Collider, position_a: Vector3, orientation_a: Quaternion, collider_b: Entity_Collider, position_b: Vector3, orientation_b: Quaternion) -> bool {
    return is_overlap_capsule_plane(collider_b, position_b, orientation_b, collider_a, position_a, orientation_a);
}

is_overlap_plane_plane :: (collider_a: Entity_Collider, position_a: Vector3, orientation_a: Quaternion, collider_b: Entity_Collider, position_b: Vector3, orientation_b: Quaternion) -> bool {
    // plane_a := *collider_a.plane;
    // plane_b := *collider_b.plane;
 
    // plane_a_normal, plane_a_height_vec, plane_a_width_vec: Vector3 = ---;
    // get_axes(orientation_a, *plane_a_normal, *plane_a_height_vec, *plane_a_width_vec);   

    // plane_b_normal, plane_b_height_vec, plane_b_width_vec: Vector3 = ---;
    // get_axes(orientation_b, *plane_b_normal, *plane_b_height_vec, *plane_b_width_vec);   

    // pt_on_b_infinite_plane := project_point_onto_plane(position_a, position_b, plane_b_normal);    
    // diff_to_pt_on_b_infinite_plane := pt_on_b_infinite_plane - position_b;
    // clamped_width_dist_on_b := clamp(dot(diff_to_pt_on_b_infinite_plane, plane_b_width_vec), -plane_b.width*0.5, plane_b.width*0.5);
    // clamped_height_dist_on_b := clamp(dot(diff_to_pt_on_b_infinite_plane, plane_b_height_vec), -plane_b.half_height, plane_b.half_height);

    // clamped_pt_on_b := position_b + plane_b_width_vec * clamped_width_dist_on_b + plane_b_height_vec * clamped_height_dist_on_b;

    // pt_on_a_infinite_plane := project_point_onto_plane(clamped_pt_on_b, position_a, plane_a_normal);
    // diff_to_pt_on_a_infinite_plane := pt_on_a_infinite_plane - position_a;
    // abs_width_dist_on_a := abs(dot(diff_to_pt_on_a_infinite_plane, plane_a_width_vec));
    // abs_height_dist_on_a := abs(dot(diff_to_pt_on_a_infinite_plane, plane_a_height_vec));

    // return abs_width_dist_on_a < plane_a.width * 0.5 && abs_height_dist_on_a < plane_a.half_height;
    return false;
}

// note: this algorithm doesn't work. (worked out counter-example on paper) it *could* be part of a bad iterative solution, but that's it.
is_overlap_plane_box :: (collider_a: Entity_Collider, position_a: Vector3, orientation_a: Quaternion, collider_b: Entity_Collider, position_b: Vector3, orientation_b: Quaternion) -> bool {
    // plane_a := *collider_a.plane;
    // box_b   := *collider_b.box;

    // plane_a_normal, plane_a_height_vec, plane_a_width_vec: Vector3 = ---;
    // get_axes(orientation_a, *plane_a_normal, *plane_a_height_vec, *plane_a_width_vec);   

    // box_fore, box_up, box_right: Vector3 = ---;
    // get_axes(orientation_b, *box_fore, *box_up, *box_right);

    // pt_on_infinite_plane := project_point_onto_plane(position_b, position_a, plane_a_normal);
    // diff_to_pt_on_infinite_plane := pt_on_infinite_plane - position_a;

    // clamped_width_dist := clamp(dot(diff_to_pt_on_infinite_plane, plane_a_width_vec), -plane_a.width*0.5, plane_a.width*0.5);
    // clamped_height_dist := clamp(dot(diff_to_pt_on_infinite_plane, plane_a_height_vec), -plane_a.half_height, plane_a.half_height);
    // clamped_pt_on_plane := position_a + plane_a_width_vec * clamped_width_dist + plane_a_height_vec * clamped_height_dist;
    
    // diff_to_clamped_pt := clamped_pt_on_plane - position_b;
    // box_abs_width_dist := abs(dot(diff_to_clamped_pt, box_right));
    // box_abs_length_dist := abs(dot(diff_to_clamped_pt, box_fore));
    // box_abs_height_dist := abs(dot(diff_to_clamped_pt, box_up));

    // return box_abs_width_dist < box_b.width * 0.5
    //     && box_abs_length_dist < box_b.length * 0.5
    //     && box_abs_height_dist < box_b.half_height;
    return false;
}

is_overlap_plane_aabb :: (collider_a: Entity_Collider, position_a: Vector3, orientation_a: Quaternion, collider_b: Entity_Collider, position_b: Vector3, orientation_b: Quaternion) -> bool {
    // plane_a := *collider_a.plane;
    // box_b   := *collider_b.box;

    // plane_a_normal, plane_a_height_vec, plane_a_width_vec: Vector3 = ---;
    // get_axes(orientation_a, *plane_a_normal, *plane_a_height_vec, *plane_a_width_vec);   

    // pt_on_infinite_plane := project_point_onto_plane(position_b, position_a, plane_a_normal);
    // diff_to_pt_on_infinite_plane := pt_on_infinite_plane - position_a;

    // clamped_width_dist := clamp(dot(diff_to_pt_on_infinite_plane, plane_a_width_vec), -plane_a.width*0.5, plane_a.width*0.5);
    // clamped_height_dist := clamp(dot(diff_to_pt_on_infinite_plane, plane_a_height_vec), -plane_a.half_height, plane_a.half_height);
    // clamped_pt_on_plane := position_a + plane_a_width_vec * clamped_width_dist + plane_a_height_vec * clamped_height_dist;
    
    // diff_to_clamped_pt := clamped_pt_on_plane - position_b;
    // return abs(diff_to_clamped_pt.x) < box_b.width * 0.5
    //     && abs(diff_to_clamped_pt.y) < box_b.length * 0.5
    //     && abs(diff_to_clamped_pt.z) < box_b.half_height;
    return false;
}

// ------------------------------------------------------------------------------------------------------- box

is_overlap_box_sphere :: inline (collider_a: Entity_Collider, position_a: Vector3, orientation_a: Quaternion, collider_b: Entity_Collider, position_b: Vector3, orientation_b: Quaternion) -> bool {
    return is_overlap_sphere_box(collider_b, position_b, orientation_b, collider_a, position_a, orientation_a);
}

is_overlap_box_capsule :: inline (collider_a: Entity_Collider, position_a: Vector3, orientation_a: Quaternion, collider_b: Entity_Collider, position_b: Vector3, orientation_b: Quaternion) -> bool {
    return is_overlap_capsule_box(collider_b, position_b, orientation_b, collider_a, position_a, orientation_a);
}

is_overlap_box_plane :: inline (collider_a: Entity_Collider, position_a: Vector3, orientation_a: Quaternion, collider_b: Entity_Collider, position_b: Vector3, orientation_b: Quaternion) -> bool {
    return is_overlap_plane_box(collider_b, position_b, orientation_b, collider_a, position_a, orientation_a);
}

is_overlap_box_box :: (collider_a: Entity_Collider, position_a: Vector3, orientation_a: Quaternion, collider_b: Entity_Collider, position_b: Vector3, orientation_b: Quaternion) -> bool {
    box_a := *collider_a.box;
    box_b := *collider_b.box;

    // fore, up, right
    box_a_axes: [3]Vector3 = ---;
    get_axes(orientation_a, *box_a_axes[0], *box_a_axes[1], *box_a_axes[2]);

    box_b_axes: [3]Vector3 = ---;
    get_axes(orientation_b, *box_b_axes[0], *box_b_axes[1], *box_b_axes[2]);

    // from Real Time Collision Detection, Christer Ericson 

    // separating axis theorem: for two convex hulls, if they don't overlap, there must be a plane separating them. in other words, projections along the normal of that plane will be non-overlapping.

    t := position_b - position_a;
    b_rel_pos := Vector3.{dot(t, box_a_axes[0]), dot(t, box_a_axes[1]), dot(t, box_a_axes[2])};

    ERROR :: SMALL_NUMBER;
    // b's rotation relative to a
    b_rel_rot: Matrix3 = ---;
    abs_b_rel_rot: Matrix3 = ---;

    for i : 0..2 {
        for j : 0..2 {
            b_rel_rot.coef[i][j] = dot(box_a_axes[i], box_b_axes[j]);
            // ERROR is added to account for errors where two edges are nearly parallel, and so their cross product is near zero
            abs_b_rel_rot.coef[i][j] = abs(b_rel_rot.coef[i][j]) + ERROR;
        }
        // test for separation along a's axes
        a_extent_along_axis := box_a.extent.component[i];
        b_extent_along_axis := 
              box_b.extent.x * abs_b_rel_rot.coef[i][0] 
            + box_b.extent.y * abs_b_rel_rot.coef[i][1] 
            + box_b.extent.z * abs_b_rel_rot.coef[i][2];
        distance := abs(b_rel_pos.component[i]);
        if distance > a_extent_along_axis + b_extent_along_axis then return false;
    }

    for 0..2 {
        // test for separation along b's axes
        a_extent_along_axis := 
              box_a.extent.x * abs_b_rel_rot.coef[0][it] 
            + box_a.extent.y * abs_b_rel_rot.coef[1][it] 
            + box_a.extent.z * abs_b_rel_rot.coef[2][it];
        b_extent_along_axis := box_b.extent.component[it];
        distance := abs(
              b_rel_pos.x * b_rel_rot.coef[0][it] 
            + b_rel_pos.y * b_rel_rot.coef[1][it] 
            + b_rel_pos.z * b_rel_rot.coef[2][it]
        );
        if distance > a_extent_along_axis + b_extent_along_axis then return false;
    }

    // test for separation along axes orthogonal to edge pairs between the boxes

    test_axis_orthogonal_to_edge_pair :: (a_0: s32, a_coef_0: s32, a_coef_1: s32, b_0: s32, b_coef_0: s32, b_coef_1: s32, $same_order: bool) #expand {
        // a's second trio of values swaps the first and second from the first trio
        a_1 := a_coef_0;
        a_coef_2 := a_0;
        a_coef_3 := a_coef_1;
        // b's second trio of values swaps the first and third from the first trio
        b_1 := b_coef_1;
        b_coef_2 := b_coef_0;
        b_coef_3 := b_0;

        a_extent_along_axis := 
              `box_a.extent.component[a_0] * `abs_b_rel_rot.coef[a_coef_0][a_coef_1] 
            + `box_a.extent.component[a_1] * `abs_b_rel_rot.coef[a_coef_2][a_coef_3];
        b_extent_along_axis := 
              `box_b.extent.component[b_0] * `abs_b_rel_rot.coef[b_coef_0][b_coef_1] 
            + `box_b.extent.component[b_1] * `abs_b_rel_rot.coef[b_coef_2][b_coef_3];
        #if same_order {
            distance := abs(
                  `b_rel_pos.component[a_0] * `b_rel_rot.coef[a_coef_0][a_coef_1] 
                - `b_rel_pos.component[a_1] * `b_rel_rot.coef[a_coef_2][a_coef_3]
            );
        } else {
            distance := abs(
                  `b_rel_pos.component[a_1] * `b_rel_rot.coef[a_coef_2][a_coef_3] 
                - `b_rel_pos.component[a_0] * `b_rel_rot.coef[a_coef_0][a_coef_1]
            );
        }
        if distance > a_extent_along_axis + b_extent_along_axis then `return false;
    } 

    // ax, bx
    test_axis_orthogonal_to_edge_pair(
        1, 2, 0,
        1, 0, 2,
        false
    );
    // ax, by
    test_axis_orthogonal_to_edge_pair(
        1, 2, 1,
        0, 0, 2,
        false
    );
    // ax, bz
    test_axis_orthogonal_to_edge_pair(
        1, 2, 2,
        0, 0, 1,
        false
    );
    // ay, bx
    test_axis_orthogonal_to_edge_pair(
        0, 2, 0,
        1, 1, 2,
        true
    );
    // ay, by
    test_axis_orthogonal_to_edge_pair(
        0, 2, 1,
        0, 1, 2,
        true
    );
    // ay, bz
    test_axis_orthogonal_to_edge_pair(
        0, 2, 2,
        0, 1, 1,
        true
    );
    // az, bx
    test_axis_orthogonal_to_edge_pair(
        0, 1, 0,
        1, 2, 2,
        false
    );
    // az, by
    test_axis_orthogonal_to_edge_pair(
        0, 1, 1,
        0, 2, 2,
        false
    );
    // az, bz
    test_axis_orthogonal_to_edge_pair(
        0, 1, 2,
        0, 2, 1,
        false
    );

    return true;
}

is_overlap_box_aabb :: inline (collider_a: Entity_Collider, position_a: Vector3, orientation_a: Quaternion, collider_b: Entity_Collider, position_b: Vector3, orientation_b: Quaternion) -> bool {
    return is_overlap_box_box(collider_b, position_b, orientation_b, collider_a, position_a, QUATERNION_IDENTITY);
}

// ------------------------------------------------------------------------------------------------------- aabb

is_overlap_aabb_sphere :: inline (collider_a: Entity_Collider, position_a: Vector3, orientation_a: Quaternion, collider_b: Entity_Collider, position_b: Vector3, orientation_b: Quaternion) -> bool {
    return is_overlap_sphere_aabb(collider_b, position_b, orientation_b, collider_a, position_a, orientation_a);
}

is_overlap_aabb_capsule :: inline (collider_a: Entity_Collider, position_a: Vector3, orientation_a: Quaternion, collider_b: Entity_Collider, position_b: Vector3, orientation_b: Quaternion) -> bool {
    return is_overlap_capsule_aabb(collider_b, position_b, orientation_b, collider_a, position_a, orientation_a);
}

is_overlap_aabb_plane :: inline (collider_a: Entity_Collider, position_a: Vector3, orientation_a: Quaternion, collider_b: Entity_Collider, position_b: Vector3, orientation_b: Quaternion) -> bool {
    return is_overlap_plane_aabb(collider_b, position_b, orientation_b, collider_a, position_a, orientation_a);
}

is_overlap_aabb_box :: inline (collider_a: Entity_Collider, position_a: Vector3, orientation_a: Quaternion, collider_b: Entity_Collider, position_b: Vector3, orientation_b: Quaternion) -> bool {
    return is_overlap_box_box(collider_b, position_b, QUATERNION_IDENTITY, collider_a, position_a, orientation_a);
}

is_overlap_aabb_aabb :: (collider_a: Entity_Collider, position_a: Vector3, orientation_a: Quaternion, collider_b: Entity_Collider, position_b: Vector3, orientation_b: Quaternion) -> bool {
    aabb_a := *collider_a.aabb;
    aabb_b := *collider_b.aabb;
    abs_pos_diff := abs(position_a - position_b);
    return abs_pos_diff.x < aabb_a.half_width + aabb_b.half_width
        && abs_pos_diff.y < aabb_a.half_length + aabb_b.half_length
        && abs_pos_diff.z < aabb_a.half_height + aabb_b.half_height;
}

// is_overlap_box_box_my_take :: (collider_a: Entity_Collider, position_a: Vector3, orientation_a: Quaternion, collider_b: Entity_Collider, position_b: Vector3, orientation_b: Quaternion) -> bool {
//     box_a := *collider_a.box;
//     box_b := *collider_b.box;

//     box_a_fore, box_a_up, box_a_right: Vector3 = ---;
//     get_axes(orientation_a, *box_a_fore, *box_a_up, *box_a_right);

//     box_b_fore, box_b_up, box_b_right: Vector3 = ---;
//     get_axes(orientation_b, *box_b_fore, *box_b_up, *box_b_right);

//     // populate normals for separating axis test
//     // separating axis theorem: for two convex hulls, if they don't overlap, there must be a plane separating them. in other words, projections along the normal of that plane will be non-overlapping.
//     separating_axis_normals: [15]Vector3 = ---;
//     separating_axis_normals[0]  = box_a_fore;
//     separating_axis_normals[1]  = box_a_up;
//     separating_axis_normals[2]  = box_a_right;
//     separating_axis_normals[3]  = box_b_fore;
//     separating_axis_normals[4]  = box_b_up;
//     separating_axis_normals[5]  = box_b_right;
//     n := 6;
//     for i : 0..2 {
//         for j : 3..5 {
//             scaled_sin_t_vec := cross(separating_axis_normals[i], separating_axis_normals[j]);
//             if length_squared(scaled_sin_t_vec) < VERY_SMALL_NUMBER {
//                 // the normals are (roughly) parallel (and so on the same plane)
//                 // use another vec from the j pool to get the normal of the plane the j vec is on, but the i vec may not be
//                 j2 := increment_wrap(j, 3, 5); 
//                 normal := cross(separating_axis_normals[i], separating_axis_normals[j2]);
//                 scaled_sin_t_vec = cross(separating_axis_normals[i], normal);
//             }
//             separating_axis_normals[n] = scaled_sin_t_vec;
//             n += 1;
//         }
//     }

//     points_a: [8]Vector3;
//     points_b: [8]Vector3;
//     get_box_points(position_a, box_a_fore * box_a.half_length, box_a_up * box_a.half_height, box_a_right * box_a.half_width, *points_a);
//     get_box_points(position_b, box_b_fore * box_b.half_length, box_b_up * box_b.half_height, box_b_right * box_b.half_width, *points_b);

//     min_projection_a :=  FLOAT32_MAX;
//     max_projection_a := -FLOAT32_MAX;
//     min_projection_b :=  FLOAT32_MAX;
//     max_projection_b := -FLOAT32_MAX;

//     for sa_normal : separating_axis_normals {
//         if length_squared(sa_normal) < VERY_SMALL_NUMBER then continue;

//         for points_a {
//             projection_a := dot(points_a[it_index], sa_normal);
//             projection_b := dot(points_b[it_index], sa_normal);
//             if it_index == 0 {
//                 min_projection_a = projection_a;
//                 max_projection_a = projection_a;
//                 min_projection_b = projection_b;
//                 max_projection_b = projection_b;
//             } else {
//                 min_projection_a = min(projection_a, min_projection_a);
//                 max_projection_a = max(projection_a, max_projection_a);
//                 min_projection_b = min(projection_b, min_projection_b);
//                 max_projection_b = max(projection_b, max_projection_b);
//             }
//         }

//         if !ordered_ranges_overlap(Vector2.{min_projection_a, max_projection_a}, Vector2.{min_projection_b, max_projection_b}) {
//             return false;
//         }
//     }

//     return true;
// }