
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