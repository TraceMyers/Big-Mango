
// todo: raycast channels (collis channels?)
// todo: raycast multi

RAYCAST_DEFAULT_MAX_DISTANCE :: 999_999.9;

Packed_Collider :: struct {
    collider: Entity_Collider;
    position: Vector3;
    orientation: Quaternion;
}

Collider_Raycast_Result :: struct {
    hit_entity: Entity_Ref;
    hit_location: Vector3;
    hit_normal: Vector3;
    hit_distance: float;
    is_hit: bool;
    origin_inside_collider: bool;
    projected_origin_to_surface: bool;
    normal_is_degenerate: bool;
    normal_is_inverted: bool;
}

Collider_Raycast_Request :: struct {
    ray: Ray3;
    max_distance: float;
    origin_inside_collider_rules: struct {
        hit_where: enum u8 {
            NO_HIT;
            RAY_ORIGIN;
            INNER_INTERSECTION;
        } = .NO_HIT;
        // only matters if hit_where is .RAY_ORIGIN. if false, origin is the hit location. if true, get the closest location on the surface.
        project_ray_origin_to_surface: bool;
        // if false, use the outward-facing normal of the hit. if true, treat the inner intersection as the true hit, so the normal is the inner normal.
        invert_inner_intersection_hit_normal: bool;
    };
}

raycast :: (request: Collider_Raycast_Request, out_result: *Collider_Raycast_Result) -> bool {
    collider_data: Packed_Collider = ---;
    last_entity := find_last_set_bit(*entities.in_use);
    // todo: grid
    cur_result: Collider_Raycast_Result = ---;
    out_result.* = .{hit_distance=FLOAT32_MAX};
    for 0..last_entity {
        cur_result.is_hit = false;
        e_phys := *entity_physics_core[it];
        e_props := get_entity_physics_properties(xx it);
        packed_collider := Packed_Collider.{e_props.body_collider, e_phys.position, e_phys.orientation};
        if e_props.body_collider.type == {
        case .SPHERE;
            raycast_sphere(request, packed_collider, *cur_result);
        case;
            continue;
        }
        if cur_result.is_hit && cur_result.hit_distance < out_result.hit_distance {
            out_result.* = cur_result;
            out_result.hit_entity = .{xx it, entities[it].id};
        }
    }
    return out_result.is_hit;
}

raycast_sphere_hit_calculation :: inline (sphere_center: Vector3, sphere_radius: float, ray_origin: Vector3, ray_direction: Vector3, line_pt: Vector3, line_pt_dist_sq: float, out_result: *Collider_Raycast_Result) {
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

raycast_sphere :: (using request: Collider_Raycast_Request, collider_data: Packed_Collider, out_result: *Collider_Raycast_Result) -> bool {
    assert(is_normalized(ray.direction, 0.001));
    out_result.* = .{};

    sphere_center    := collider_data.position;
    sphere_radius    := collider_data.collider.sphere.radius;
    sphere_radius_sq := square(sphere_radius);

    toward_ray_origin_diff := ray.origin - sphere_center;
    toward_ray_origin_dist_sq := length_squared(toward_ray_origin_diff);

    ray_length := ifx max_distance <= 0 then RAYCAST_DEFAULT_MAX_DISTANCE else max_distance;

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
        } else if origin_inside_collider_rules.hit_where == .INNER_INTERSECTION {
            // hit is true only if ray intersects an inside face of the volume
            ray_end := sphere_center + ray.origin + ray.direction * ray_length;
            ray_end_diff := ray_end - sphere_center;
            ray_end_dist_sq := length_squared(ray_end_diff);
            if ray_end_dist_sq >= sphere_radius_sq {
                out_result.is_hit = true;

                line_pt := closest_point_on_line(*sphere_center, *ray);
                line_pt_dist_sq := distance_squared(line_pt, sphere_center);

                raycast_sphere_hit_calculation(sphere_center, sphere_radius, ray.origin, -ray.direction, line_pt, line_pt_dist_sq, out_result);
                if origin_inside_collider_rules.invert_inner_intersection_hit_normal {
                    out_result.hit_normal *= -1;
                    out_result.normal_is_inverted = true;
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

    out_result.normal_is_degenerate |= abs(length_squared(out_result.hit_normal) - 1.0) > SMALL_NUMBER;
    return out_result.is_hit;
}