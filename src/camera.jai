
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


// point_at :: (camera: *Camera, point: Vector3) {
//     direction := point - camera.position;
//     normalize(*direction, fallback=.{z=1});
    // set_forward_direction(camera, direction);
// }

view_matrix :: (camera: *Camera) -> Matrix4 {
    // making inverse of transform that takes the forward axis to the forward vector. we can get this effect
    // by just passing the relative normalized axes of the camera
    rotation := make_matrix_from_rows(right_direction(camera), -up_direction(camera), -fore_direction(camera));
    // 'moving the world' into place by removing the camera's position
    return translate(rotation, -camera.position);
}

projection_matrix :: (camera: *Camera, viewport: Vector2) -> Matrix4 {
    if camera.projection == .ORTHOGRAPHIC {
        v := viewport / (2.0 * camera.orthographic.scale);
        return orthographic_projection_matrix(-v.x, v.x, -v.y, v.y, NEAR_PLANE, FAR_PLANE, true);
    } else { // PERSPECTIVE
        fov_radians := camera.perspective.vertical_fov * (PI / 180.0);
        aspect := ifx camera.perspective.aspect_ratio == 0.0 then viewport.y / viewport.x else camera.perspective.aspect_ratio;
        return make_projection_matrix(fov_radians, aspect, NEAR_PLANE, FAR_PLANE, 0, 0, true);
    }
}

view_projection_matrix :: (camera: *Camera, viewport: Vector2) -> Matrix4 {
    view := view_matrix(camera);
    proj := projection_matrix(camera, viewport);
    return proj * view;
}

// camera_init :: inline (projection: CameraProjection) {
//     cameras[camera_index] = Camera_Make(projection);
// }

// Camera_Get :: inline () -> *Camera {
//     return *cameras[camera_index];
// }

// Camera_Position :: inline () -> Vector3 {
//     return cameras[camera_index].position;
// }

// Camera_Right :: inline () -> Vector3 {
//     return Right(*cameras[camera_index]);
// }

// Camera_Up :: inline () -> Vector3 {
//     return Up(*cameras[camera_index]);
// }

// Camera_Forward :: inline () -> Vector3 {
//     return Forward(*cameras[camera_index]);
// }

// Camera_Point_At :: inline (point: Vector3) {
//     Point_At(*cameras[camera_index], point);
// }

// Camera_Set_Position :: inline (position: Vector3) {
//     cameras[camera_index].position = position;
// }

// Camera_Set_Direction :: inline (direction: Vector3) {
//     Set_Direction(*cameras[camera_index], direction);
// }

// Camera_View_Matrix :: inline () -> Matrix4 {
//     return View_Matrix(*cameras[camera_index]);
// }

// Camera_Projection_Matrix :: inline (viewport := Vector2.{}) -> Matrix4 {
//     if viewport == Vector2.{} {
//         window_width, window_height := Window_Dimensions(float32);
//         return Projection_Matrix(*cameras[camera_index], .{window_width, window_height});
//     } else {
//         return Projection_Matrix(*cameras[camera_index], viewport);
//     }
// }

// Camera_View_Projection_Matrix :: inline (viewport := Vector2.{}) -> Matrix4 {
//     if viewport == Vector2.{} {
//         window_width, window_height := Window_Dimensions(float32);
//         return View_Projection_Matrix(*cameras[camera_index], .{window_width, window_height});
//     } else {
//         return View_Projection_Matrix(*cameras[camera_index], viewport);
//     }
// }

// Cache_Camera_View_Projection :: inline (viewport := Vector2.{}) {
//     camera_view_projection = Camera_View_Projection_Matrix(viewport);
// }

// Get_Cached_Camera_View_Projection :: inline () -> Matrix4 {
//     return camera_view_projection;
// }