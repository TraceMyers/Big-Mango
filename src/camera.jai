
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

// get_screen_clip
