
draw_line :: inline (start: Vector3, end: Vector3, color: Vector4) {
    draw_line(start, end, color, color);
}

draw_line :: (start: Vector3, end: Vector3, start_color: Vector4, end_color: Vector4) {
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