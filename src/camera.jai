
NEAR_PLANE :: 0.1;
FAR_PLANE :: 10_000.0;

Camera_Projection :: enum {
    NONE;
    ORTHOGRAPHIC;
    PERSPECTIVE;
}

Camera_Settings_Orthographic :: struct {
    scale := 1.0;
}

Camera_Settings_Perspective :: struct {
    vertical_fov := 100.0; // degrees
    aspect_ratio := 0.0; // 0 for default
}

Camera :: struct {
    projection := Camera_Projection.NONE;
    using settings: union {
        orthographic: Camera_Settings_Orthographic = ---;
        perspective: Camera_Settings_Perspective = ---;
    }
}

camera_make :: (projection: Camera_Projection) -> Camera {
    c := Camera.{projection=projection};
    if #complete projection == {
    case .NONE;
        assert(false);
    case .ORTHOGRAPHIC;
        c.orthographic = .{};
    case .PERSPECTIVE;
        c.perspective = .{};
    }
    return c;
} 

view_matrix :: (camera: *Entity) -> Matrix4 {
    assert(is_set(*camera.flags, .USES_CAMERA));
    // making inverse of transform that takes the forward axis to the forward vector. we can get this effect
    // by just passing the relative normalized axes of the camera
    rotation := make_matrix_from_rows(camera.axes.right, -camera.axes.up, -camera.axes.fore);
    // 'moving the world' into place by removing the camera's position
    return translate(rotation, -camera.center);
}

get_aspect_ratio :: inline (camera: *Entity, viewport: Vector2, $which := enum { X_OVER_Y; Y_OVER_X; }.X_OVER_Y) -> float {
    #if which == .X_OVER_Y {
        return ifx camera.perspective.aspect_ratio == 0.0 then viewport.x / viewport.y else camera.perspective.aspect_ratio;
    } else {
        return ifx camera.perspective.aspect_ratio == 0.0 then viewport.y / viewport.x else 1.0 / camera.perspective.aspect_ratio;
    }
}

projection_matrix :: (camera: *Entity, viewport: Vector2) -> Matrix4 {
    assert(is_set(*camera.flags, .USES_CAMERA));
    if camera.projection == .ORTHOGRAPHIC {
        v := viewport / (2.0 * camera.orthographic.scale);
        return orthographic_projection_matrix(-v.x, v.x, -v.y, v.y, NEAR_PLANE, FAR_PLANE, true);
    } else { // PERSPECTIVE
        fov_radians := camera.perspective.vertical_fov * (PI / 180.0);
        aspect := get_aspect_ratio(camera, viewport);
        return make_projection_matrix(fov_radians, aspect, NEAR_PLANE, FAR_PLANE, 0, 0, true);
    }
}

view_projection_matrix :: (camera: *Entity, viewport: Vector2) -> Matrix4 {
    assert(is_set(*camera.flags, .USES_CAMERA));
    view := view_matrix(camera);
    proj := projection_matrix(camera, viewport);
    return proj * view;
}

get_mouse_cursor_ray :: (camera: *Entity, viewport: Vector2) -> Ray3 {
    assert(is_set(*camera.flags, .USES_CAMERA));
    theta := (camera.perspective.vertical_fov * 0.5) * (PI / 180.0);
    half_y_dist := NEAR_PLANE * tan(theta); // tan(theta) = opp / adj
    clip_rect_height := half_y_dist * 2.0;
    clip_rect_width := get_aspect_ratio(camera, viewport) * clip_rect_height;

    p: Win32.POINT;
    Win32.GetCursorPos(*p);
    success := Win32.ScreenToClient(window, *p) != 0;
    if success {
        cursor_position.x = p.x;
        cursor_position.y = p.y;
        cursor_norm_position.x = p.x.(float) / viewport.x.(float);
        cursor_norm_position.y = p.y.(float) / viewport.y.(float);
    }

    norm_clip_rect_center := Vector2.{0.5,0.5};
    norm_center_diff := cursor_norm_position - norm_clip_rect_center;
    world_clip_rect_diff := norm_center_diff * Vector2.{clip_rect_width, -clip_rect_height};

    world_clip_rect_center := camera.center + camera.axes.fore * NEAR_PLANE;
    world_clip_rect_cursor_pos := world_clip_rect_center + world_clip_rect_diff.x * camera.axes.right + world_clip_rect_diff.y * camera.axes.up;
    cursor_raycast_dir := normalize(world_clip_rect_cursor_pos - camera.center);

    return .{look_origin(camera), cursor_raycast_dir};
}

// get_screen_clip
