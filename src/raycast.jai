
// todo: raycast channels (collis channels?)
// todo: raycast multi

RAYCAST_DEFAULT_MAX_DISTANCE :: 999_999.9;

Raycast_Result :: struct {
    hit_entity: Entity_Ref;
    hit_location: Vector3;
    hit_normal: Vector3;
    hit_distance: float;
    is_hit: bool;
    hit_back_face: bool;
    origin_inside_collider: bool;
    projected_origin_to_surface: bool;
    normal_is_degenerate: bool;
    normal_is_back_face: bool;
}

Raycast_Request :: struct {
    ray: Ray3;
    max_distance := -1.0;
    origin_inside_collider_rules: struct {
        // where should the hit be if the origin is inside the collider?
        hit_where: enum u8 {
            // doesn't count as a hit
            NO_HIT;
            // origin location is the hit location (can be projected to surface if that option is true)
            RAY_ORIGIN;
            // override can_hit_back_face as true in the case where the origin is inside the volume
            BACK_FACE;
        } = .NO_HIT;
        // only matters if hit_where is .RAY_ORIGIN. if false, origin is the hit location. if true, get the closest location on the surface.
        project_ray_origin_to_surface: bool;
    };
    hit_back_face: bool;
    // if false, use the outward-facing normal of the hit. if true, treat the inner intersection as the true hit, so the normal is the inner normal.
    flip_back_face_hit_normal: bool;
}

raycast_ray_length :: inline (using request: Raycast_Request) -> float {
    return ifx max_distance < 0 then RAYCAST_DEFAULT_MAX_DISTANCE else max_distance;
}

raycast_can_hit_back_face :: inline (using request: Raycast_Request, origin_inside_collider: bool) -> bool {
    if origin_inside_collider {
        return hit_back_face || origin_inside_collider_rules.hit_where == .BACK_FACE;
    } else {
        return hit_back_face;
    }
} 

raycast :: (request: Raycast_Request, out_result: *Raycast_Result) -> bool {
    cur_result: Raycast_Result = ---;
    out_result.* = .{hit_distance=FLOAT32_MAX};
    // todo: grid + sphere intersection test
    for e : entities {
        cur_result.is_hit = false;
        if e.shape.type == {
        case .SPHERE;
            raycast_sphere(request, e.body, *cur_result);
        case .RECT;
            // raycast_rect(request, packed_collider, *cur_result, it);
        case;
            continue;
        }
        if cur_result.is_hit && cur_result.hit_distance < out_result.hit_distance {
            out_result.* = cur_result;
            out_result.hit_entity = e.ref;
        }
    }
    return out_result.is_hit;
}

raycast_sphere_hit_calculation :: inline (sphere_center: Vector3, sphere_radius: float, ray_origin: Vector3, ray_direction: Vector3, line_pt: Vector3, line_pt_dist_sq: float, out_result: *Raycast_Result) {
    projection_tri_edge_dist_sq := square(sphere_radius) - line_pt_dist_sq;
    if projection_tri_edge_dist_sq < VERY_SMALL_NUMBER {
        out_result.hit_location = sphere_center - ray_direction * sphere_radius;
        out_result.hit_normal = -ray_direction;
    } else {
        projection_tri_edge_dist := sqrt(projection_tri_edge_dist_sq);
        out_result.hit_location = line_pt - ray_direction * projection_tri_edge_dist;
        out_result.hit_normal = normalize(out_result.hit_location - sphere_center);
    }
    out_result.hit_distance = distance(ray_origin, out_result.hit_location);
}

raycast_sphere :: (using request: Raycast_Request, body: Physics_Body, out_result: *Raycast_Result) -> bool {
    assert(is_normalized(ray.direction, 0.0001));
    out_result.* = .{};

    sphere_center    := body.center;
    sphere_radius    := body.shape.sphere.radius;
    sphere_radius_sq := square(sphere_radius);

    toward_ray_origin_diff := ray.origin - sphere_center;
    toward_ray_origin_dist_sq := length_squared(toward_ray_origin_diff);

    ray_length := raycast_ray_length(request);
    can_hit_back_face := raycast_can_hit_back_face(request, true);

    if toward_ray_origin_dist_sq < sphere_radius_sq {
        // origin inside volume
        out_result.origin_inside_collider = true;

        if origin_inside_collider_rules.hit_where == .RAY_ORIGIN {
            // hit is true if ray origin is inside volume (and it is)
            out_result.is_hit = true;

            if toward_ray_origin_dist_sq < VERY_SMALL_NUMBER {
                out_result.normal_is_degenerate = true;
            } else {
                toward_ray_origin_dist := sqrt(toward_ray_origin_dist_sq);
                out_result.hit_normal = toward_ray_origin_diff / toward_ray_origin_dist;
            }

            if !origin_inside_collider_rules.project_ray_origin_to_surface {
                out_result.hit_location = ray.origin;
            } else {
                out_result.projected_origin_to_surface = true;
                if out_result.normal_is_degenerate {
                    // send back the normal used for projection, even though the true normal is degenerate
                    out_result.hit_normal = .{0,0,1};
                }
                out_result.hit_location = sphere_center + out_result.hit_normal * sphere_radius;
                out_result.hit_distance = distance(ray.origin, out_result.hit_location);
            }
        } else if can_hit_back_face {
            // hit is true only if ray intersects an inside face of the volume
            ray_end := sphere_center + ray.origin + ray.direction * ray_length;
            ray_end_diff := ray_end - sphere_center;
            ray_end_dist_sq := length_squared(ray_end_diff);
            if ray_end_dist_sq >= sphere_radius_sq {
                out_result.is_hit = true;
                out_result.hit_back_face = true;

                line_pt := closest_point_on_line(*sphere_center, *ray);
                line_pt_dist_sq := distance_squared(line_pt, sphere_center);

                raycast_sphere_hit_calculation(sphere_center, sphere_radius, ray.origin, -ray.direction, line_pt, line_pt_dist_sq, out_result);
                if flip_back_face_hit_normal {
                    out_result.hit_normal *= -1;
                } else {
                    out_result.normal_is_back_face = true;
                }
            }
        } else { // NO_HIT
            // hit is never true when origin is inside the volume
        }
    } else {
        // if we can get the t of the projection, we can know if it's normal-forward or normal-backward
        ray_end := sphere_center + ray.origin + ray.direction * ray_length;
        line_pt, segment_pt: Vector3;
        closest_point_on_line_and_segment(*sphere_center, *ray.origin, *ray_end, *line_pt, *segment_pt);
        segment_pt_dist_sq := distance_squared(segment_pt, sphere_center);
        if segment_pt_dist_sq < sphere_radius_sq {
            out_result.is_hit = true;
            line_pt_dist_sq := distance_squared(line_pt, sphere_center);
            raycast_sphere_hit_calculation(sphere_center, sphere_radius, ray.origin, ray.direction, line_pt, line_pt_dist_sq, out_result);
        }
    }

    out_result.normal_is_degenerate |= !is_normalized(out_result.hit_normal, SMALL_NUMBER);
    return out_result.is_hit;
}

// raycast_rect :: (using request: Raycast_Request, collider_data: Packed_Collider, out_result: *Raycast_Result, entity_index: s64) -> bool {
//     assert(is_normalized(ray.direction, 0.0001));
//     out_result.* = .{};

//     rect_center        := collider_data.position;
//     rect_half_width    := collider_data.collider.rect.half_width;
//     rect_half_height   := collider_data.collider.rect.half_height;
//     rect_normal        := precalculated_fore_directions[entity_index];
//     rect_height_vec    := precalculated_up_directions[entity_index];
//     rect_width_vec     := cross(rect_height_vec, rect_normal);

//     ray_length := raycast_ray_length(request);
//     can_hit_back_face := hit_back_face;

//     ray_direction_cos_t := dot(rect_normal, ray.direction);
//     aiming_for_backside := ray_direction_cos_t >= 0;

//     if !aiming_for_backside || can_hit_back_face {
//         origin_projection, projection_t := project_point_onto_plane(ray.origin, rect_center, rect_normal);
//         // the two given dot products should have a product with a negative sign if a hit is possible. to see this, build out a table of the four possible combinations of [sign of dp of normals] and [sign of projection norm dist along plane normal]
//         t_mix_test := ray_direction_cos_t * projection_t;
//         if t_mix_test < 0 {
//             // heading is valid
//             origin_projection_diff := origin_projection - ray.origin;
//             toward_projection_scaled_cos_t := dot(origin_projection_diff, ray.direction);
//             assert(toward_projection_scaled_cos_t > 0);

//             origin_projection_dist := abs(dot(origin_projection_diff, rect_normal));
//             inv_cos_t := origin_projection_dist / toward_projection_scaled_cos_t;
//             distance_to_intersection := origin_projection_dist * inv_cos_t; 
//             if distance_to_intersection <= ray_length {
//                 // ray intersects the infinite plane
//                 hit_location := ray.origin + ray.direction * distance_to_intersection;
//                 plane_center_to_hit_diff := hit_location - rect_center;
//                 hit_distance_along_height_axis := abs(dot(plane_center_to_hit_diff, rect_height_vec));
//                 hit_distance_along_width_axis := abs(dot(plane_center_to_hit_diff, rect_width_vec));
//                 if hit_distance_along_height_axis <= rect_half_height && hit_distance_along_width_axis <= rect_half_width {
//                     // infinite plane intersection is within the bounds of the finite plane
//                     out_result.hit_location = hit_location;
//                     out_result.hit_normal = rect_normal;
//                     out_result.hit_distance = distance_to_intersection;
//                     out_result.is_hit = true;
//                     out_result.hit_back_face = aiming_for_backside;
//                     if out_result.hit_back_face && !flip_back_face_hit_normal {
//                         out_result.hit_normal *= -1.0;
//                         out_result.normal_is_back_face = true;
//                     }
//                 }
//             }
//         }
//     }

//     out_result.normal_is_degenerate |= !is_normalized(out_result.hit_normal, SMALL_NUMBER);
//     return out_result.is_hit;
// }