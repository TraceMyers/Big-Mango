
draw_line :: inline (start: Vector3, end: Vector3, color: Color4f) {
    draw_line(start, end, color, color);
}

draw_line :: (start: Vector3, end: Vector3, start_color: Color4f, end_color: Color4f) {
    if lines.count + 2 > LINES_MAX then return;
    array_add(*lines, .{
        .{
            position = .{xyz=start,w=1},
            color = start_color
        }, 
        .{
            position = .{xyz=end,w=1},
            color = end_color
        }
    });
}

draw_sphere :: (center: Vector3, radius: float, color: Color4f, poly_count := Sphere_Poly_Count.MEDIUM) {
    array_add(*sphere_draws, .{center, radius, color, poly_count});
}

draw_aabb :: (shape: Collision_Shape, position: Vector3, orientation: Quaternion, color: Color4f) {
    aabb: AABB = ---;
    get_aabb(shape, position, orientation, *aabb);
    draw_aabb(aabb, color);
}

draw_aabb :: (aabb: AABB, color: Color4f) {
    points: [8]Vector3;
    get_aabb_points(aabb, *points);
    for Box_Edges {
        draw_line(points[it.a], points[it.b], color);
    }
}

draw_all_body_collider_aabbs :: () {
    for 1..entity_patch_infos.count-1 {
        if entity_patch_infos[it].patch_flags & .STATIC_MESH {
            e := get_entity_at(it);
            draw_aabb(e.body.shape, e.center, e.orientation, COLOR4F_RED);
        }
    }
}

draw_line_with_points :: (start: Vector3, end: Vector3, start_color: Color4f, end_color: Color4f, start_point_color: Color4f, end_point_color: Color4f, point_radius := 0.4, omit_start_point := false, omit_end_point := false) {
    draw_line(start, end, start_color, end_color);
    if !omit_start_point {
        draw_sphere(start, point_radius, start_point_color, .LOW);
    }
    if !omit_end_point {
        draw_sphere(end, point_radius, end_point_color, .LOW);
    }
}

draw_line_with_points :: inline (start: Vector3, end: Vector3, color: Color4f, point_radius := 0.4, omit_start_point := false, omit_end_point := false) {
    draw_line_with_points(start, end, color, color, color, color, point_radius, omit_start_point, omit_end_point);
}

// draw_capsule :: (request: Capsule_Draw_Request) {
//     array_add(*capsules_to_draw, request);
// }

// Capsule_Draw_Request :: struct {
//     segment_point_a: Vector3;
//     segment_point_b: Vector3;
//     radius: float;
//     color: Color4b;
// }

// capsules_to_draw: [..]Capsule_Draw_Request;

Capsule_Draw_Push_Constants :: struct {
    segment_point_a_x: float;
    segment_point_a_y: float;
    segment_point_a_z: float;
    segment_point_b_x: float;
    segment_point_b_y: float;
    segment_point_b_z: float;
    norm_radius: float;
    color_r: float;
    color_g: float;
    color_b: float;
    color_a: float;
}