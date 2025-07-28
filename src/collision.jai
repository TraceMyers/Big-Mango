
// todo: it's convenient to clamp positions to the bounds of the collision grid so that the game doesn't have to crash
// when things go outside the bounds (and it's convenient for aabb projection), but some handling needs to be done to make sure that doesn't happen often. otherwise,
// a situation might occur where entities that are pretty far apart are bunched up into the edge cells, overpopulating them.
// todo: find a way to capture all declaration names and types in a block and export it to a struct, then insert
// code that copies all of the values of the block into the struct.

// world size: 2000 x 2000
// cell size: 10 x 10 
// world cell counts: 200 x 200 = 80_000

COLLISION_DEBUG :: true;
AABB_OVERLAP_BUFFER :: 1.0;

#if COLLISION_DEBUG {
    collision_assert :: assert;
} else {
    collision_assert :: (b: bool) #expand {}
}

_collision :: (stage: Boot_Stage) -> bool {
    if stage == .STARTUP {
        context.collision_overlaps.allocator = temp;
        // init_collision_grid(.{}, .{2000,2000}, .{10,10});
    }
    return true;
}

solve_contacts :: () {
    entity_ct := get_entity_count();
    if entity_ct < 2 {
        return;
    }

    Move_Entity :: struct {
        body: *Collision_Body;
        axes: *Axes;
        movement: *Entity_Movement;
    }

    for e1 : 0..entity_ct-2 {
        if entity_collision_channels[e1] == 0 then continue;
        entity_1_body               := *entity_collision_bodies[e1];
        entity_1_compressed_axes    := *entity_compressed_axes[e1];
        entity_1_movement           := *entity_movements[e1];
        entity_1_axes: Axes = ---;
        decompress_axes(entity_1_compressed_axes, *entity_1_axes);
        entity_1_props              := get_physics_properties_at(e1);

        entity_1_aabb: AABB = ---;
        get_aabb(entity_1_body.shape, entity_1_body.center, entity_1_axes.fore, entity_1_axes.up, entity_1_axes.right, *entity_1_aabb);

        for e2 : e1+1..entity_ct-1 {
            if (entity_collision_channels[e1] & entity_collision_channels[e2]) == 0 then continue;
            entity_2_body               := *entity_collision_bodies[e2];
            entity_2_compressed_axes    := *entity_compressed_axes[e2];
            entity_2_movement           := *entity_movements[e2];
            entity_2_axes: Axes = ---;
            decompress_axes(entity_2_compressed_axes, *entity_2_axes);
            entity_2_props              := get_physics_properties_at(e2);

            entity_2_aabb: AABB = ---;
            get_aabb(entity_2_body.shape, entity_2_body.center, entity_2_axes.fore, entity_2_axes.up, entity_2_axes.right, *entity_2_aabb);

            if !is_overlap_aabb_aabb(entity_1_aabb, entity_2_aabb) {
                continue;
            }

            result: Contact_Result;
            is_contact: bool;
            // very for now. just move up to collis and kill velocity along normals
            move_entity_2: bool;
            if entity_1_body.shape.type == .RECT && entity_2_body.shape.type == .SPHERE {
                is_contact = solve_potential_contact(entity_2_body.*, entity_2_axes, entity_1_body.*, entity_1_axes, FIXED_TIME_STEP, *result);
                move_entity_2 = true;
            } else {
                is_contact = solve_potential_contact(entity_1_body.*, entity_1_axes, entity_2_body.*, entity_2_axes, FIXED_TIME_STEP, *result);
            }

            if !is_contact {
                continue;
            }

            move_entity_a: Move_Entity = ---;
            move_entity_b: Move_Entity;
            if move_entity_2 {
                move_entity_a = .{entity_2_body, *entity_2_axes, entity_2_movement};
            } else {
                move_entity_a = .{entity_1_body, *entity_1_axes, entity_1_movement};
                if entity_2_props.mass > IMMOVABLE_ENTITY_MASS {
                    move_entity_b = .{entity_2_body, *entity_2_axes, entity_2_movement};
                }
            }

            // don't worry about ccd stuff...
            if move_entity_b.movement == null {
                using move_entity_a;
                speed_in_direction_opposite_hit_normal := dot(body.velocity, -result.contact_normal);
                body.velocity += result.contact_normal * speed_in_direction_opposite_hit_normal;
            } else {
                a_speed_in_direction_of_hit_normal := dot(move_entity_a.body.velocity, result.contact_normal);
                move_entity_a.body.velocity -= a_speed_in_direction_of_hit_normal;
                b_speed_in_direction_of_hit_normal := dot(move_entity_b.body.velocity, result.contact_normal);
                move_entity_b.body.velocity -= b_speed_in_direction_of_hit_normal;
            }

            entity_patch_infos[e1].flags |= .COLLIDING_WITH_SOMETHING;
            entity_patch_infos[e2].flags |= .COLLIDING_WITH_SOMETHING;
        }
    }

    for e : 0..entity_ct-1 {
        if entity_collision_channels[e] == 0 then continue;
        entity_body := *entity_collision_bodies[e];
        entity_axes: Axes = ---;
        decompress_axes(*entity_compressed_axes[e], *entity_axes);
        entity_aabb: AABB = ---;
        get_aabb(entity_body.shape, entity_body.center, entity_axes.fore, entity_axes.up, entity_axes.right, *entity_aabb);

        if entity_patch_infos[e].flags & .COLLIDING_WITH_SOMETHING {
            draw_aabb(entity_aabb, .{r=1});
        } else {
            draw_aabb(entity_aabb, .{g=1});
        }
    }
}

solve_potential_contact :: (body_a: Collision_Body, axes_a: Axes, body_b: Collision_Body, axes_b: Axes, time_step: float, out_result: *Contact_Result) -> bool {
    shape_a := *body_a.shape;
    shape_b := *body_b.shape;
    if shape_a.type == {
    case .SPHERE;
        if shape_b.type == {
        case .SPHERE;
            #if COLLISION_DEBUG {
                return Procedure_Capture_Duplicate.solve_potential_contact_sphere_sphere(body_a, axes_a, body_b, axes_b, time_step, out_result);
            } else {
                return solve_potential_contact_sphere_sphere(body_a, axes_a, body_b, axes_b, time_step, out_result);
            }
        case .CAPSULE;
        case .RECT;
            #if COLLISION_DEBUG {
                return Procedure_Capture_Duplicate.solve_potential_contact_sphere_rect(body_a, axes_a, body_b, axes_b, time_step, out_result);
            } else {
                return solve_potential_contact_sphere_rect(body_a, axes_a, body_b, axes_b, time_step, out_result);
            }
        case .BOX;
        case .AABB;
        case .HALF_SPACE;
        }
    case .CAPSULE;
        if shape_b.type == {
        case .SPHERE;
        case .CAPSULE;
        case .RECT;
        case .BOX;
        case .AABB;
        case .HALF_SPACE;
        }
    case .RECT;
        if shape_b.type == {
        case .SPHERE;
        case .CAPSULE;
        case .RECT;
        case .BOX;
        case .AABB;
        case .HALF_SPACE;
        }
    case .BOX;
        if shape_b.type == {
        case .SPHERE;
        case .CAPSULE;
        case .RECT;
        case .BOX;
        case .AABB;
        case .HALF_SPACE;
        }
    case .AABB;
        if shape_b.type == {
        case .SPHERE;
        case .CAPSULE;
        case .RECT;
        case .BOX;
        case .AABB;
        case .HALF_SPACE;
        }
    case .HALF_SPACE;
        if shape_b.type == {
        case .SPHERE;
        case .CAPSULE;
        case .RECT;
        case .BOX;
        case .AABB;
        case .HALF_SPACE;
        }
    }
    return false;
}

solve_potential_contact_sphere_sphere :: (body_a: Collision_Body, axes_a: Axes, body_b: Collision_Body, axes_b: Axes, time_step: float, out_result: *Contact_Result) -> bool {
    sphere_a := *body_a.shape.sphere;
    sphere_b := *body_b.shape.sphere;

    contact_radius := sphere_a.radius + sphere_b.radius;
    contact_radius_sq := square(contact_radius);
    if contact_radius < VERY_SMALL_NUMBER {
        out_result.norm_time = 1;
        return false;
    }

    // solve t = 0 contacts.
    current_diff := body_a.center - body_b.center;
    current_dist_sq := length_squared(current_diff);
    if current_dist_sq < contact_radius_sq {
        out_result.norm_time = 0;
        if current_dist_sq < VERY_SMALL_NUMBER {
            // colliders are two close to calculate a normal. just need to pick something
            out_result.contact_normal = .{x=1};
            out_result.contact_depth_if_time_is_zero = max(sphere_a.radius, sphere_b.radius);
        } else {
            contact_dist := sqrt(current_dist_sq);
            out_result.contact_normal = current_diff / contact_dist;
            out_result.contact_depth_if_time_is_zero = contact_radius - contact_dist;
        }
        out_result.a_local_space_contact_point = -out_result.contact_normal * sphere_a.radius;
        out_result.b_local_space_contact_point =  out_result.contact_normal * sphere_b.radius;
        return true;
    }

    sphere_a_sweep_diff         := body_a.velocity * time_step;
    sphere_a_sweep_begin        := body_a.center;
    sphere_a_sweep_end          := body_a.center + sphere_a_sweep_diff;

    b_closest_pt_on_line, norm_dist_along_sweep := closest_point_on_line(*body_b.center, *sphere_a_sweep_begin, *sphere_a_sweep_end);

    dist_sq_from_line := distance_squared(b_closest_pt_on_line, body_b.center);
    if dist_sq_from_line >= contact_radius_sq {
        out_result.norm_time = 1.0;
        return false;
    }

    clamped_norm_dist_along_sweep := clamp(norm_dist_along_sweep, 0, 1);
    b_closest_pt_on_sweep := sphere_a_sweep_begin + sphere_a_sweep_diff * clamped_norm_dist_along_sweep;
    dist_sq_from_sweep := distance_squared(b_closest_pt_on_sweep, body_b.center);
    if dist_sq_from_sweep >= contact_radius_sq {
        out_result.norm_time = 1.0;
        return false;
    }

    move_from_line_projection_dist      := sqrt(contact_radius_sq - dist_sq_from_line);
    sphere_a_sweep_length_sq            := length_squared(sphere_a_sweep_diff);
    move_from_line_projection_norm_dist : float = ---;

    if sphere_a_sweep_length_sq < VERY_SMALL_NUMBER {
        move_from_line_projection_norm_dist = 0;
    } else {
        sphere_a_sweep_length := sqrt(sphere_a_sweep_length_sq);
        move_from_line_projection_norm_dist = move_from_line_projection_dist / sphere_a_sweep_length;
    }

    normal_sign         := -sign(clamped_norm_dist_along_sweep);
    norm_time           := norm_dist_along_sweep + normal_sign * move_from_line_projection_norm_dist;
    a_contact_position  := sphere_a_sweep_begin + body_a.velocity * out_result.norm_time;
    contact_diff        := a_contact_position - body_b.center;

    out_result.contact_normal = normalize(contact_diff);
    is_contact := true;
    if norm_time >= 1 {
        out_result.norm_time = 1;
        is_contact = false;
    }

    // for spheres, just ignore the axes and use world axes
    out_result.a_local_space_contact_point = -out_result.contact_normal * sphere_a.radius;
    out_result.b_local_space_contact_point =  out_result.contact_normal * sphere_b.radius;

    return is_contact;
} @capture_body_as_struct

solve_potential_contact_sphere_rect :: (body_a: Collision_Body, axes_a: Axes, body_b: Collision_Body, axes_b: Axes, time_step: float, out_result: *Contact_Result) -> bool {
    sphere_a    := *body_a.shape.sphere;
    rect_b      := *body_b.shape.rect;

    contact_radius := sphere_a.radius;
    contact_radius_sq := square(contact_radius);
    if contact_radius < VERY_SMALL_NUMBER {
        out_result.norm_time = 1;
        return false;
    }

    sphere_a_sweep_diff         := body_a.velocity * time_step;
    sphere_a_sweep_begin        := body_a.center;
    sphere_a_sweep_end          := body_a.center + sphere_a_sweep_diff;

    rect_b_normal       := axes_b.fore;
    rect_b_axis_up      := axes_b.up;
    rect_b_axis_right   := axes_b.right;

    sweep_begin_projected_to_rect := clamp_point_to_rect(sphere_a_sweep_begin, body_b.center, rect_b_axis_up, rect_b_axis_right, rect_b.half_height, rect_b.half_width);

    current_diff        := sphere_a_sweep_begin - sweep_begin_projected_to_rect;
    current_dist_signed := dot(rect_b_normal, current_diff);

    // if the sphere is behind the rect and will stay behind it, there is no collision
    if current_dist_signed < 0 {
        out_result.norm_time = 1;
        return false;
    }

    current_dist := current_dist_signed;
    out_result.contact_normal = rect_b_normal;

    // solve t = 0 contacts.
    if current_dist < contact_radius {
        out_result.norm_time = 0;
        out_result.contact_depth_if_time_is_zero = contact_radius - current_dist;
        out_result.a_local_space_contact_point = -out_result.contact_normal * sphere_a.radius;
        out_result.b_local_space_contact_point = world_space_to_local_space(sweep_begin_projected_to_rect - body_b.center, rect_b_normal, rect_b_axis_up, rect_b_axis_right);
        return true;
    }

    // heading away from rect's plane
    sweep_signed_dist_along_normal := dot(sphere_a_sweep_diff, rect_b_normal);
    if sweep_signed_dist_along_normal >= 0 {
        out_result.norm_time = 1;
        return false;
    }

    sweep_dist_sq := length_squared(sphere_a_sweep_diff);
    // we don't have a contact at = 0 and we're only moving imperceptibly if at all, so no contact
    // todo: this may cause bugs if things move *very* slowly. how to address?
    if sweep_dist_sq < VERY_SMALL_NUMBER {
        out_result.norm_time = 1;
        return false;
    }

    // reprojection is needed here for raycasting. we don't know that the point on the rect wasn't clamped
    // it seems wasteful to project to the plane after projecting to the rect... but actually zero instructions are saved when doing it in reverse as far as I can tell.
    sweep_begin_projected_to_plane, signed_dist_to_plane_projection := project_point_onto_plane(body_a.center, body_b.center, rect_b_normal);
    dist_to_plane_projection := abs(signed_dist_to_plane_projection);

    // the ratio of the line intersection's sidelength to the segment's sidelength can be used to scale the segment difference so as to represent the ray intersection hypotenuse minus the distance s.t. the sphere is touching the rect rather than its center being on the rect (without any normalization / sqrt)
    sweep_dist_along_normal := -sweep_signed_dist_along_normal;
    buffered_dist_to_plane_projection := dist_to_plane_projection - contact_radius;
    out_result.norm_time = buffered_dist_to_plane_projection / sweep_dist_along_normal;

    if out_result.norm_time <= 0 || out_result.norm_time >= 1 {
        out_result.norm_time = 1;
        return false;
    }

    sphere_location_at_point_of_contact := sphere_a_sweep_begin + sphere_a_sweep_diff * out_result.norm_time;
    out_result.a_local_space_contact_point = -out_result.contact_normal * sphere_a.radius;
    b_world_space_contact_point := sphere_location_at_point_of_contact + out_result.a_local_space_contact_point;
    out_result.b_local_space_contact_point = world_space_to_local_space(b_world_space_contact_point - body_b.center, rect_b_normal, rect_b_axis_up, rect_b_axis_right);

    return true;
} @capture_body_as_struct 

get_aabb_extent :: (shape: Collision_Shape, axis_fore: Vector3, axis_up: Vector3, axis_right: Vector3) -> Vector3 {
    if #complete shape.type == {
    case .SPHERE;
        using shape.sphere;
        return .{radius, radius, radius};
    case .CAPSULE;
        using shape.capsule;
        segment_half_len := half_height - radius;
        segment_point := axis_up * segment_half_len;
        return abs(segment_point) + Vector3.{radius,radius,radius};
    case .RECT;
        using shape.rect;
        abs_point_1 := abs(axis_up * half_height + axis_right * half_width);
        abs_point_2 := abs(axis_up * half_height - axis_right * half_width);
        return max(abs_point_1, abs_point_2) + SMALL_NUMBER;
    case .BOX;
        using shape.box;
        height_vec := abs(axis_up * half_height);
        length_vec := abs(axis_fore * half_length);
        width_vec  := abs(axis_right * half_width);
        return max(height_vec, max(length_vec, width_vec));
    case .AABB;
        using shape.aabb;
        return .{half_width, half_length, half_height};
    case .HALF_SPACE;
        // you *can* have plane bounds in the case where the plane exactly aligns with an axis, but in that case
        // its bounds have area 0, which isn't useful for collision pruning.
        return .{FLOAT32_MAX, FLOAT32_MAX, FLOAT32_MAX};
    }
}

// get_bounding_sphere_radius :: (collider: Collider) -> float {
//     if #complete collider.type == {
//     case .SPHERE;
//         using collider.sphere;
//         return radius;
//     case .CAPSULE;
//         using collider.capsule;
//         return half_height; 
//     case .RECT;
//         using collider.rect;
//         return sqrt(square(half_width) + square(half_height));
//     case .BOX;
//         using collider.box;
//         return sqrt(square(half_width) + square(half_length) + square(half_height));
//     case .AABB;
//         using collider.aabb;
//         return sqrt(square(half_width) + square(half_length) + square(half_height));
//     case .HALF_SPACE;
//         return FLOAT32_MAX;
//     }
// }

get_aabb :: inline (shape: Collision_Shape, position: Vector3, orientation: Quaternion, out_aabb: *AABB)  {
    axis_fore, axis_up, axis_right: Vector3 = ---;
    get_axes(orientation, *axis_fore, *axis_up, *axis_right);
    get_aabb(shape, position, axis_fore, axis_up, axis_right, out_aabb);
}

get_aabb :: inline (shape: Collision_Shape, position: Vector3, axis_fore: Vector3, axis_up: Vector3, axis_right: Vector3, out_aabb: *AABB) {
    out_aabb.center = position;
    out_aabb.extent = get_aabb_extent(shape, axis_fore, axis_up, axis_right);
}

collision_grid: []Collision_Grid_Allocation;
collision_grid_allocator: Nesting_Allocator(8);
collision_grid_origin: Vector2;
collision_grid_dimensions: Int_Vector2;
collision_cell_dimensions: Vector2;
inv_collision_cell_dimensions: Vector2;