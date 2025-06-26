
// NOTE: colliders should just be always upright. serves the needs of the game and I know it in and out.

Cylinder_Collider :: struct {
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
        CYLINDER;
        BOX;
    };
    using data: union {
        height: float;
        cylinder: Cylinder_Collider = ---;
        box: Box_Collider = ---;
    };
}

to_bottom_position :: inline (using c: *Entity_Collider, center: Vector3) -> Vector3 {
    return center - Vector3.{0,0,height*0.5};
}

draw_collider :: (c: *Entity_Collider, position: *Vector3, forward: *Vector2, color: *Color4f, lines : s32 = 32, position_at_bottom := true) {
    bot_pos := ifx position_at_bottom then position.* else to_bottom_position(c, position);
    if c.type == {
    case .CYLINDER;
        draw_cylinder(c, *bot_pos, forward, color, lines);
    case .BOX;
    }
}

// instead of drawing the typical bottom face circle and lines up the side, only draw a line that takes
// one of the infinitely many shortest paths from one bottom center to the top center. each set of lines runs perfectly
// across the surface, as opposed to the circle, which only crudely represents the edge.
// i just think it'll look nice
draw_cylinder :: (c: *Entity_Collider, bottom_position: *Vector3, forward: *Vector2, color: *Color4f, lines : s32 = 32) {
    assert(lines > 0);
    bot_pos := bottom_position;
    top_pos := bot_pos + Vector3.{0,0,c.height};

    lines = max(lines, 12);
    line_ct := ceil_to_multiple(lines, 3);
    step_ct := line_ct / 3;

    outward := WORLD_RIGHT;
    step_quat: Quaternion;
    rotate(*step_quat, .{0,0,1}, 2.0 * PI / step_ct.(float));

    for 0..step_ct-1 {
        bot_edge_pt := bot_pos + outward * c.cylinder.radius;
        top_edge_pt := bot_edge_pt + Vector3.{0,0,c.height};
        draw_line(bot_pos, bot_edge_pt, color.*);
        draw_line(bot_edge_pt, top_edge_pt, color.*);
        draw_line(top_edge_pt, top_pos, color.*);
        outward = rotate(outward, step_quat);
    }
}

// solve_potential_collision :: inline (entity_a: *Entity, entity_b: *Entity) -> bool {
//     unused_dir: Vector3 = ---;
//     unused_gap: float = ---;
//     return solve_potential_collision(entity_a, entity_b, *unused_dir, *unused_gap);
// }

// solve_potential_collision :: inline (entity_a: *Entity, entity_b: *Entity, out_collision_dir: *Vector3, out_gap: *float) -> bool {
//     return solve_potential_collision(*entity_a.position, *entity_a.velocity, *precalculated_forward_directions[entity_a.index], entity_a.physics_properties, *entity_b.position, *entity_b.velocity, *precalculated_forward_directions[entity_b.index], entity_b.physics_properties, out_collision_dir, out_gap);
// }

// solve_potential_collision :: (position_a: *Vector3, velocity_a: *Vector3, forward_a: *Vector2, properties_a: *Physics_Properties, position_b: *Vector3, velocity_b: *Vector3, forward_b: *Vector2, properties_b: *Physics_Properties, out_collision_dir: *Vector3, out_gap: *float) -> bool {
//     collider_a := *physics_properties_a.body_collider;
//     collider_b := *physics_properties_b.body_collider;
//     if collider_a.type == {
//     case .CYLINDER;
//     case .BOX;
//     }
// }