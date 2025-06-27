
draw_line :: inline (start: Vector3, end: Vector3, color: Color4f) {
    draw_line(start, end, color, color);
}

draw_line :: (start: Vector3, end: Vector3, start_color: Color4f, end_color: Color4f) {
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

draw_capsule :: (request: Capsule_Draw_Request) {
    array_add(*capsules_to_draw, request);
}

Capsule_Draw_Request :: struct {
    segment_point_a: Vector3;
    segment_point_b: Vector3;
    radius: float;
    color: Color4b;
}

capsules_to_draw: [..]Capsule_Draw_Request;

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