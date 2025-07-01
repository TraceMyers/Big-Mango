
Potential_Collision :: struct {
    entity_a: u16;
    entity_b: u16;
}
potential_collisions: [..]Potential_Collision;
// NOTE: colliders should just be always upright. serves the needs of the game and I know it in and out.

Capsule_Collider :: struct {
    height: float;
    radius: float;
}

Box_Collider :: struct {
    height: float;
    width: float;
    length: float;
}

Entity_Collider :: struct {
    type: enum u8 {
        CAPSULE;
        BOX;
    };
    using data: union {
        height: float;
        capsule: Capsule_Collider = ---;
        box: Box_Collider = ---;
    };
}

to_bottom_position :: inline (using c: *Entity_Collider, center: Vector3) -> Vector3 {
    return center - Vector3.{z=height*0.5};
}

populate_potential_contacts :: () {
    // todo: grid
    last_entity := find_last_set_bit(*entities.in_use);
    for i : 0..last_entity-1 {
        if entities[i].type != .STATIC_MESH then continue;
        for j : i+1..last_entity {
            assert(bit_is_set(*entities.in_use, j));
            if entities[j].type != .STATIC_MESH then continue;
            array_add(*potential_collisions, .{xx i, xx j});
        }
    }
}

solve_potential_contacts :: () {
    inv_delta_time := 1.0 / delta_time;
    for potential_collisions {
        phys_a := *entity_physics_core[it.entity_a];
        phys_b := *entity_physics_core[it.entity_b];
        props_a := get_entity_physics_properties(it.entity_a);
        props_b := get_entity_physics_properties(it.entity_b);
        // todo: precalculated forward directions
        dummy_forward: Vector2;

        collis_gap: float;
        collis_vec: Vector3; // toward A

        is_collision := solve_potential_collision(*phys_a.position, *phys_a.linear_velocity, *dummy_forward, props_a, *phys_b.position, *phys_b.linear_velocity, *dummy_forward, props_b, *collis_vec, *collis_gap);

        if is_collision {
            SOFTENING_FACTOR :: 0.7;
            // inv delta time applied because collision resolution is applying a position delta through velocity
            impulse := collis_vec * (-collis_gap) * inv_delta_time * SOFTENING_FACTOR;
            inv_mass_sum := 1.0 / (props_a.mass + props_b.mass);
            phys_a.linear_velocity += impulse * (inv_mass_sum * props_b.mass);
            phys_b.linear_velocity -= impulse * (inv_mass_sum * props_a.mass);
        }
    }
    array_reset_keeping_memory(*potential_collisions);
}

solve_potential_collision :: inline (entity_a: *Entity, entity_b: *Entity) -> bool {
    unused_dir: Vector3 = ---;
    unused_gap: float = ---;
    return solve_potential_collision(entity_a, entity_b, *unused_dir, *unused_gap);
}

solve_potential_collision :: inline (entity_a: *Entity, entity_b: *Entity, out_collision_dir: *Vector3, out_gap: *float) -> bool {
    return solve_potential_collision(*entity_a.position, *entity_a.linear_velocity, *precalculated_forward_directions[entity_a.index], entity_a.physics_properties, *entity_b.position, *entity_b.linear_velocity, *precalculated_forward_directions[entity_b.index], entity_b.physics_properties, out_collision_dir, out_gap);
}

solve_potential_collision :: (position_a: *Vector3, velocity_a: *Vector3, forward_a: *Vector2, properties_a: *Physics_Properties, position_b: *Vector3, velocity_b: *Vector3, forward_b: *Vector2, properties_b: *Physics_Properties, out_collision_dir: *Vector3, out_gap: *float) -> bool {
    collider_a := *properties_a.body_collider;
    collider_b := *properties_b.body_collider;
    if collider_a.type == {
    case .CAPSULE;
        if collider_b.type == {
        case .CAPSULE;
            return solve_collision_capsule_capsule(position_a, velocity_a, forward_a, properties_a, position_b, velocity_b, forward_b, properties_b, out_collision_dir, out_gap);
        case .BOX;
        }
    case .BOX;
    }
    return false;
}

solve_collision_capsule_capsule :: (position_a: *Vector3, velocity_a: *Vector3, forward_a: *Vector2, properties_a: *Physics_Properties, position_b: *Vector3, velocity_b: *Vector3, forward_b: *Vector2, properties_b: *Physics_Properties, out_collision_dir: *Vector3, out_gap: *float) -> bool {
    // for simplicty's sake rn, assuming upright.
    // also they were filtered for z overlap already

    cylinder_a := *properties_a.body_collider.capsule;
    cylinder_b := *properties_b.body_collider.capsule;

    a_pos_next := position_a.* + velocity_a.* * delta_time;
    b_pos_next := position_b.* + velocity_b.* * delta_time;

    a_bot := a_pos_next;
    a_bot.z = max(a_bot.z + cylinder_a.radius, 0.0);
    a_top := a_pos_next;
    a_top.z = max(a_top.x + (cylinder_a.height - cylinder_a.radius), 0.0);

    b_bot := b_pos_next;
    b_bot.z = max(b_bot.z + cylinder_b.radius, 0.0);
    b_top := b_pos_next;
    b_top.z = max(b_top.x + (cylinder_b.height - cylinder_b.radius), 0.0);

    a_closest_point, b_closest_point: Vector3;
    dist := distance_between_line_segments(*a_bot, *a_top, *b_bot, *b_top, *a_closest_point, *b_closest_point);

    if is_nan_is_inf(dist) {
        return false;
    }
    
    buffer_distance := cylinder_a.radius + cylinder_b.radius;
    out_gap.* = dist - buffer_distance;
    out_collision_dir.* = (a_closest_point - b_closest_point) * (1.0 / dist); 

    if out_gap.* >= 0 {
        return false;
    }

    return true;
}