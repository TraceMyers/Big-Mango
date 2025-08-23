
do_debug_draws :: () {
    for #v2 < 0..line_draws.count-1 {
        // $todo: copying the line draws into another line draws array is silly.
        line := *line_draws[it];
        array_add(*lines, .{
            .{
                position = .{xyz=line.start,w=1},
                color = line.start_color,
            }, 
            .{
                position = .{xyz=line.end,w=1},
                color = line.end_color,
            }
        });
        array_add(*layers, line.layer);
        if line.start_point_radius > 0 {
            draw_sphere(line.start, line.start_point_radius, line.start_color);
        }
        if line.end_point_radius > 0 {
            draw_sphere(line.end, line.end_point_radius, line.end_color);
        }
        line.time_remaining -= delta_time;
        if line.time_remaining <= 0 {
            array_unordered_remove_by_index(*line_draws, it);
        }
    }
}

draw_line :: inline (start: Vector3, end: Vector3, color: Color4f, duration := 0.0, layer : s8 = 0)  {
    draw_line(start, end, color, color, duration, layer=layer);
}

draw_line :: (start: Vector3, end: Vector3, start_color: Color4f, end_color: Color4f, duration := 0.0, start_point_radius := 0.0, end_point_radius := 0.0, layer : s8 = 0) {
    if lines.count + 2 > LINES_MAX then return;
    array_add(*line_draws, .{start, end, start_color, end_color, start_point_radius, end_point_radius, duration, layer});
}

draw_sphere :: (center: Vector3, radius: float, color: Color4f, poly_count := Sphere_Poly_Count.MEDIUM) {
    array_add(*sphere_draws, .{center, radius, color, poly_count});
}

draw_aabb :: (shape: Collision_Shape, position: Vector3, orientation: Quaternion, color: Color4f, layer : s8 = 0) {
    aabb: AABB = ---;
    get_aabb(shape, position, orientation, *aabb);
    draw_aabb(aabb, color, layer);
}

draw_aabb :: (aabb: AABB, color: Color4f, layer : s8 = 0) {
    points: [8]Vector3;
    get_aabb_points(aabb, *points);
    for Box_Edges {
        draw_line(points[it.a], points[it.b], color, layer=layer);
    }
}

draw_aabb :: (e: *Entity, color: Color4f, layer : s8 = 0) {
    draw_aabb(e.shape, e.center, e.orientation, color, layer);
}

draw_box :: (location: Vector3, orientation: Quaternion, dimensions: Vector3, color: Color4f) {
    array_add(*primitive_draws, .{
        shape = .{type=.BOX, box=.{dimensions.z * 0.5, dimensions.x * 0.5, dimensions.y * 0.5}},
        center = location,
        orientation = orientation,
        color = .{tint=color}
    });
}

draw_all_body_collider_aabbs :: () {
    for context.world.entities {
        draw_aabb(it.shape, it.center, it.orientation, COLOR4F_RED);
    }
}

draw_crosshair_line :: (center: Vector3, center_dist: float, length: float, dir: Vector3) {
    cross_inner_pt := center - dir * center_dist;
    cross_outer_pt := cross_inner_pt - dir * length;
    draw_line(cross_inner_pt, cross_outer_pt, .{r=1,g=1,b=1});
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

Line_Draw :: struct {
    start: Vector3;
    end: Vector3;
    start_color: Color4f;
    end_color: Color4f;
    start_point_radius: float;
    end_point_radius: float;
    time_remaining: float;
    layer: s8;
}

DRAW_IN_FRONT_LAYER_MAX :: S8_MAX;
line_draws: [..]Line_Draw;