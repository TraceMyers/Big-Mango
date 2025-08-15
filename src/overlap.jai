
// todo: this should take unit axes and it can just have a convenience wrapper that takes quaternions
is_overlap :: (collider_a: Collision_Shape, position_a: Vector3, axes_a: Axes, collider_b: Collision_Shape, position_b: Vector3, axes_b: Axes) -> bool {
    if collider_a.type == {
    case .SPHERE;
        if collider_b.type == {
        case .SPHERE;
            return is_overlap_sphere_sphere(collider_a, position_a, axes_a, collider_b, position_b, axes_b);
        case .CAPSULE;
            return is_overlap_sphere_capsule(collider_a, position_a, axes_a, collider_b, position_b, axes_b);
        case .RECT;
            return is_overlap_sphere_rect(collider_a, position_a, axes_a, collider_b, position_b, axes_b);
        case .BOX;
            return is_overlap_sphere_box(collider_a, position_a, axes_a, collider_b, position_b, axes_b);
        case .AABB;
            return is_overlap_sphere_aabb(collider_a, position_a, axes_a, collider_b, position_b, axes_b);
        case .HALF_SPACE;
            return is_overlap_sphere_half_space(collider_a, position_a, axes_a, collider_b, position_b, axes_b);
        }
    case .CAPSULE;
        if collider_b.type == {
        case .SPHERE;
            return is_overlap_capsule_sphere(collider_a, position_a, axes_a, collider_b, position_b, axes_b);
        case .CAPSULE;
            return is_overlap_capsule_capsule(collider_a, position_a, axes_a, collider_b, position_b, axes_b);
        case .RECT;
            return is_overlap_capsule_rect(collider_a, position_a, axes_a, collider_b, position_b, axes_b);
        case .BOX;
            return is_overlap_capsule_box(collider_a, position_a, axes_a, collider_b, position_b, axes_b);
        case .AABB;
            return is_overlap_capsule_aabb(collider_a, position_a, axes_a, collider_b, position_b, axes_b);
        case .HALF_SPACE;
            return is_overlap_capsule_half_space(collider_a, position_a, axes_a, collider_b, position_b, axes_b);
        }
    case .RECT;
        if collider_b.type == {
        case .SPHERE;
            return is_overlap_rect_sphere(collider_a, position_a, axes_a, collider_b, position_b, axes_b);
        case .CAPSULE;
            return is_overlap_rect_capsule(collider_a, position_a, axes_a, collider_b, position_b, axes_b);
        case .RECT;
            return is_overlap_rect_rect(collider_a, position_a, axes_a, collider_b, position_b, axes_b);
        case .BOX;
            return is_overlap_rect_box(collider_a, position_a, axes_a, collider_b, position_b, axes_b);
        case .AABB;
            return is_overlap_rect_aabb(collider_a, position_a, axes_a, collider_b, position_b, axes_b);
        case .HALF_SPACE;
        }
    case .BOX;
        if collider_b.type == {
        case .SPHERE;
            return is_overlap_box_sphere(collider_a, position_a, axes_a, collider_b, position_b, axes_b);
        case .CAPSULE;
            return is_overlap_box_capsule(collider_a, position_a, axes_a, collider_b, position_b, axes_b);
        case .RECT;
            return is_overlap_box_rect(collider_a, position_a, axes_a, collider_b, position_b, axes_b);
        case .BOX;
            return is_overlap_box_box(collider_a, position_a, axes_a, collider_b, position_b, axes_b);
        case .AABB;
            return is_overlap_box_aabb(collider_a, position_a, axes_a, collider_b, position_b, axes_b);
        case .HALF_SPACE;
            return is_overlap_box_half_space(collider_a, position_a, axes_a, collider_b, position_b, axes_b);
        }
    case .AABB;
        if collider_b.type == {
        case .SPHERE;
            return is_overlap_aabb_sphere(collider_a, position_a, axes_a, collider_b, position_b, axes_b);
        case .CAPSULE;
            return is_overlap_aabb_capsule(collider_a, position_a, axes_a, collider_b, position_b, axes_b);
        case .RECT;
            return is_overlap_aabb_rect(collider_a, position_a, axes_a, collider_b, position_b, axes_b);
        case .BOX;
            return is_overlap_aabb_box(collider_a, position_a, axes_a, collider_b, position_b, axes_b);
        case .AABB;
            return is_overlap_aabb_aabb(collider_a, position_a, axes_a, collider_b, position_b, axes_b);
        case .HALF_SPACE;
            return is_overlap_aabb_half_space(collider_a, position_a, axes_a, collider_b, position_b, axes_b);
        }
    case .HALF_SPACE;
        if collider_b.type == {
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

// ------------------------------------------------------------------------------------------------------- sphere

is_overlap_sphere_sphere :: (collider_a: Collision_Shape, position_a: Vector3, axes_a: Axes, collider_b: Collision_Shape, position_b: Vector3, axes_b: Axes) -> bool {
    sphere_a := *collider_a.sphere;
    sphere_b := *collider_b.sphere;
    combined_radii := sphere_a.radius + sphere_b.radius;
    return distance_squared(position_a, position_b) < square(combined_radii);
}

is_overlap_sphere_capsule :: (collider_a: Collision_Shape, position_a: Vector3, axes_a: Axes, collider_b: Collision_Shape, position_b: Vector3, axes_b: Axes) -> bool {
    sphere_a    := *collider_a.sphere;
    capsule_b   := *collider_b.capsule;

    capsule_up := axes_b.up;
    capsule_seg_pt_0 := position_b + capsule_up * (capsule_b.half_height - capsule_b.radius);
    capsule_seg_pt_1 := position_b - capsule_up * (capsule_b.half_height - capsule_b.radius);

    pt_on_seg := closest_point_on_line_segment(*position_a, *capsule_seg_pt_0, *capsule_seg_pt_1);
    combined_radii := sphere_a.radius + capsule_b.radius;
    return distance_squared(position_a, pt_on_seg) < square(combined_radii);
}

is_overlap_sphere_rect :: (collider_a: Collision_Shape, position_a: Vector3, axes_a: Axes, collider_b: Collision_Shape, position_b: Vector3, axes_b: Axes) -> bool {
    sphere_a    := *collider_a.sphere;
    rect_b     := *collider_b.rect;

    rect_normal := axes_b.fore;
    rect_height_vec := axes_b.up;
    rect_width_vec := axes_b.right;

    pt_on_infinite_plane := project_point_onto_plane(position_a, position_b, rect_normal);

    diff_along_plane := pt_on_infinite_plane - position_b;
    clamped_height_dist := clamp(dot(diff_along_plane, rect_height_vec), -rect_b.half_height, rect_b.half_height);
    clamped_width_dist := clamp(dot(diff_along_plane, rect_width_vec), -rect_b.half_width, rect_b.half_width);

    pt_on_rect := position_b + rect_height_vec * clamped_height_dist + rect_width_vec * clamped_width_dist;

    return distance_squared(position_a, pt_on_rect) < square(sphere_a.radius);
}

is_overlap_sphere_box :: (collider_a: Collision_Shape, position_a: Vector3, axes_a: Axes, collider_b: Collision_Shape, position_b: Vector3, axes_b: Axes) -> bool {
    sphere_a    := *collider_a.sphere;
    box_b       := *collider_b.box;
    packaged_box := Box.{position_b, box_b.extent, axes_b.fore, axes_b.up, axes_b.right};
    pt_in_box := closest_point_in_box(position_a, packaged_box);
    return distance_squared(position_a, pt_in_box) < square(sphere_a.radius);
}

is_overlap_sphere_aabb :: (collider_a: Collision_Shape, position_a: Vector3, axes_a: Axes, collider_b: Collision_Shape, position_b: Vector3, axes_b: Axes) -> bool {
    sphere_a    := *collider_a.sphere;
    aabb_b      := *collider_b.aabb;
    pt_in_box := closest_point_in_aabb(position_a, .{position_b, aabb_b.extent});
    return distance_squared(position_a, pt_in_box) < square(sphere_a.radius);
}

is_overlap_sphere_half_space :: (collider_a: Collision_Shape, position_a: Vector3, axes_a: Axes, collider_b: Collision_Shape, position_b: Vector3, axes_b: Axes) -> bool {
    sphere_a    := *collider_a.sphere;
    plane_normal := axes_b.fore;
    _, signed_dist := project_point_onto_plane(position_a, position_b, plane_normal);
    return signed_dist < sphere_a.radius;
}

// ------------------------------------------------------------------------------------------------------- capsule

is_overlap_capsule_sphere :: inline (collider_a: Collision_Shape, position_a: Vector3, axes_a: Axes, collider_b: Collision_Shape, position_b: Vector3, axes_b: Axes) -> bool {
    return is_overlap_sphere_capsule(collider_b, position_b, axes_b, collider_a, position_a, axes_a);
}

is_overlap_capsule_capsule :: (collider_a: Collision_Shape, position_a: Vector3, axes_a: Axes, collider_b: Collision_Shape, position_b: Vector3, axes_b: Axes) -> bool {
    capsule_a := *collider_a.capsule;
    capsule_b := *collider_b.capsule;

    a_up := axes_a.up;
    a_seg_pt_0 := position_a + a_up * (capsule_a.half_height - capsule_a.radius);
    a_seg_pt_1 := position_a - a_up * (capsule_a.half_height - capsule_a.radius);

    b_up := axes_b.up;
    b_seg_pt_0 := position_b + b_up * (capsule_b.half_height - capsule_b.radius);
    b_seg_pt_1 := position_b - b_up * (capsule_b.half_height - capsule_b.radius);

    pt_on_a, pt_on_b: Vector3 = ---;
    closest_point_on_each_line_segment(a_seg_pt_0, a_seg_pt_1, b_seg_pt_0, b_seg_pt_1, *pt_on_a, *pt_on_b);
    combined_radii := capsule_a.radius + capsule_b.radius;

    return distance_squared(pt_on_a, pt_on_b) < square(combined_radii);
}

is_overlap_capsule_rect :: (collider_a: Collision_Shape, position_a: Vector3, axes_a: Axes, collider_b: Collision_Shape, position_b: Vector3, axes_b: Axes) -> bool {
    capsule_a   := *collider_a.capsule;
    rect_b     := *collider_b.rect;

    a_up := axes_a.up;
    a_seg_pt_0 := position_a + a_up * (capsule_a.half_height - capsule_a.radius);
    a_seg_pt_1 := position_a - a_up * (capsule_a.half_height - capsule_a.radius);

    rect_normal := axes_b.fore;
    rect_height_vec := axes_b.up;
    rect_width_vec := axes_b.right;

    a_seg_pt_0_projected := project_point_onto_plane(a_seg_pt_0, position_b, rect_normal);
    a_seg_pt_1_projected := project_point_onto_plane(a_seg_pt_1, position_b, rect_normal);

    diff_along_plane_0 := a_seg_pt_0_projected - position_b;
    clamped_height_dist_0 := clamp(dot(diff_along_plane_0, rect_height_vec), -rect_b.half_height, rect_b.half_height);
    clamped_width_dist_0 := clamp(dot(diff_along_plane_0, rect_width_vec), -rect_b.half_width, rect_b.half_width);

    diff_along_plane_1 := a_seg_pt_1_projected - position_b;
    clamped_height_dist_1 := clamp(dot(diff_along_plane_1, rect_height_vec), -rect_b.half_height, rect_b.half_height);
    clamped_width_dist_1 := clamp(dot(diff_along_plane_1, rect_width_vec), -rect_b.half_width, rect_b.half_width);

    a_seg_pt_0_projected_and_clamped := position_b + rect_width_vec * clamped_width_dist_0 + rect_height_vec * clamped_height_dist_0;
    a_seg_pt_1_projected_and_clamped := position_b + rect_width_vec * clamped_width_dist_1 + rect_height_vec * clamped_height_dist_1;

    pt_on_a, pt_on_b: Vector3 = ---;
    closest_point_on_each_line_segment(a_seg_pt_0, a_seg_pt_1, a_seg_pt_0_projected_and_clamped, a_seg_pt_1_projected_and_clamped, *pt_on_a, *pt_on_b);

    return distance_squared(pt_on_a, pt_on_b) < square(capsule_a.radius);
}

is_overlap_capsule_box :: (collider_a: Collision_Shape, position_a: Vector3, axes_a: Axes, collider_b: Collision_Shape, position_b: Vector3, axes_b: Axes) -> bool {
    // capsule_a   := *collider_a.capsule;
    // box_b       := *collider_b.box;

    // b_inverse_rotation := Axes.{xyz=-axes_b.xyz, w=axes_b.w};
    // position_a_box_relative := position_a - position_b;
    // position_a_box_space := rotate(position_a_box_relative, b_inverse_rotation);

    // axes_a_box_space := b_inverse_rotation * axes_a;
    // a_up_box_space := up_direction(*axes_a_box_space);

    // a_seg_pt_0 := position_a_box_space + a_up_box_space * (capsule_a.half_height - capsule_a.radius);
    // a_seg_pt_1 := position_a_box_space - a_up_box_space * (capsule_a.half_height - capsule_a.radius);

    // box_extent := Vector3.{box_b.half_width, box_b.half_length, box_b.half_height};
    // pt_on_segment := closest_point_on_line_segment_from_aabb_at_origin(a_seg_pt_0, a_seg_pt_1, box_extent);
    // pt_clamped_to_box := clamp(pt_on_segment, box_extent);
    
    // return distance_squared(pt_on_segment, pt_clamped_to_box) < square(capsule_a.radius);
    return false;
}

is_overlap_capsule_aabb :: (collider_a: Collision_Shape, position_a: Vector3, axes_a: Axes, collider_b: Collision_Shape, position_b: Vector3, axes_b: Axes) -> bool {
    // capsule_a   := *collider_a.capsule;
    // box_b       := *collider_b.box;

    // position_a_box_space := position_a - position_b;
    // a_up_box_space := up_direction(*axes_a);

    // a_seg_pt_0 := position_a_box_space + a_up_box_space * (capsule_a.half_height - capsule_a.radius);
    // a_seg_pt_1 := position_a_box_space - a_up_box_space * (capsule_a.half_height - capsule_a.radius);

    // box_extent := Vector3.{box_b.half_width, box_b.half_length, box_b.half_height};
    // pt_on_segment := closest_point_on_line_segment_from_aabb_at_origin(a_seg_pt_0, a_seg_pt_1, box_extent);
    // pt_clamped_to_box := clamp(pt_on_segment, box_extent);
    
    // return distance_squared(pt_on_segment, pt_clamped_to_box) < square(capsule_a.radius);
    return false;
}

is_overlap_capsule_half_space :: (collider_a: Collision_Shape, position_a: Vector3, axes_a: Axes, collider_b: Collision_Shape, position_b: Vector3, axes_b: Axes) -> bool {
    // capsule_a := *collider_a.capsule;

    // capsule_up_axis := up_direction(*axes_a);
    // capsule_seg_pt_0 := position_a + capsule_up_axis * (capsule_a.half_height - capsule_a.radius);
    // capsule_seg_pt_1 := position_a - capsule_up_axis * (capsule_a.half_height - capsule_a.radius);

    // plane_normal := fore_direction(*axes_b);
    // _, signed_dist_0 := project_point_onto_plane(capsule_seg_pt_0, position_b, plane_normal);
    // if signed_dist_0 < capsule_a.radius then return true;

    // _, signed_dist_1 := project_point_onto_plane(capsule_seg_pt_1, position_b, plane_normal);
    // if signed_dist_1 < capsule_a.radius then return true;

    // return false;
    return false;
}

// ------------------------------------------------------------------------------------------------------- rect

is_overlap_rect_sphere :: inline (collider_a: Collision_Shape, position_a: Vector3, axes_a: Axes, collider_b: Collision_Shape, position_b: Vector3, axes_b: Axes) -> bool {
    return is_overlap_sphere_rect(collider_b, position_b, axes_b, collider_a, position_a, axes_a);
}

is_overlap_rect_capsule :: inline (collider_a: Collision_Shape, position_a: Vector3, axes_a: Axes, collider_b: Collision_Shape, position_b: Vector3, axes_b: Axes) -> bool {
    return is_overlap_capsule_rect(collider_b, position_b, axes_b, collider_a, position_a, axes_a);
}

is_overlap_rect_rect :: (collider_a: Collision_Shape, position_a: Vector3, axes_a: Axes, collider_b: Collision_Shape, position_b: Vector3, axes_b: Axes) -> bool {
    // rect_a := *collider_a.rect;
    // recrect= *collider_b.plane;
 
    // plane_a_normal, plane_a_height_vec, plane_a_width_vec: Vector3 = ---;
    // get_axes(axes_a, *plane_a_normal, *plane_a_height_vec, *plane_a_width_vec);   

    // plane_b_normal, plane_b_height_vec, plane_b_width_vec: Vector3 = ---;
    // get_axes(axes_b, *plane_b_normal, *plane_b_height_vec, *plane_b_width_vec);   

    // pt_on_b_infinite_plane := project_point_onto_plane(position_a, position_b, plane_b_normal);    
    // diff_to_pt_on_b_infinite_plane := pt_on_b_infinite_plane - position_b;
    // clamped_width_dist_on_b := clamp(dot(diff_to_pt_on_b_infinite_plane, plane_b_width_vec), -plane_b.width*0.5, plane_b.width*0.5);
    // clamped_height_dist_on_b := clamp(dot(diff_to_pt_on_b_infinite_plane, plane_b_height_vec), -plane_b.half_height, plane_b.half_height);

    // clamped_pt_on_b := position_b + plane_b_width_vec * clamped_width_dist_on_b + plane_b_height_vec * clamped_height_dist_on_b;

    // pt_on_a_infinite_plane := project_point_onto_plane(clamped_pt_on_b, position_a, plane_a_normal);
    // diff_to_pt_on_a_infinite_plane := pt_on_a_infinite_plane - position_a;
    // abs_width_dist_on_a := abs(dot(diff_to_pt_on_a_infinite_plane, plane_a_width_vec));
    // abs_height_dist_on_a := abs(dot(diff_to_pt_on_a_infinite_plane, plane_a_height_vec));

    // return abs_width_dist_on_a < plane_a.width * 0.5 && abs_height_dist_on_a < plane_a.half_height;
    return false;
}

// note: this algorithm doesn't work. (worked out counter-example on paper) it *could* be part of a bad iterative solution, but that's it.
is_overlap_rect_box :: (collider_a: Collision_Shape, position_a: Vector3, axes_a: Axes, collider_b: Collision_Shape, position_b: Vector3, axes_b: Axes) -> bool {
    // plane_a := *collider_a.plane;
    // box_b   := *collider_b.box;

    // plane_a_normal, plane_a_height_vec, plane_a_width_vec: Vector3 = ---;
    // get_axes(axes_a, *plane_a_normal, *plane_a_height_vec, *plane_a_width_vec);   

    // box_fore, box_up, box_right: Vector3 = ---;
    // get_axes(axes_b, *box_fore, *box_up, *box_right);

    // pt_on_infinite_plane := project_point_onto_plane(position_b, position_a, plane_a_normal);
    // diff_to_pt_on_infinite_plane := pt_on_infinite_plane - position_a;

    // clamped_width_dist := clamp(dot(diff_to_pt_on_infinite_plane, plane_a_width_vec), -plane_a.width*0.5, plane_a.width*0.5);
    // clamped_height_dist := clamp(dot(diff_to_pt_on_infinite_plane, plane_a_height_vec), -plane_a.half_height, plane_a.half_height);
    // clamped_pt_on_plane := position_a + plane_a_width_vec * clamped_width_dist + plane_a_height_vec * clamped_height_dist;
    
    // diff_to_clamped_pt := clamped_pt_on_plane - position_b;
    // box_abs_width_dist := abs(dot(diff_to_clamped_pt, box_right));
    // box_abs_length_dist := abs(dot(diff_to_clamped_pt, box_fore));
    // box_abs_height_dist := abs(dot(diff_to_clamped_pt, box_up));

    // return box_abs_width_dist < box_b.width * 0.5
    //     && box_abs_length_dist < box_b.length * 0.5
    //     && box_abs_height_dist < box_b.half_height;
    return false;
}

is_overlap_rect_aabb :: (collider_a: Collision_Shape, position_a: Vector3, axes_a: Axes, collider_b: Collision_Shape, position_b: Vector3, axes_b: Axes) -> bool {
    // rect_a := *collider_a.plane;
    // box_b   := *collider_b.box;

    // plane_a_normal, plane_a_height_vec, plane_a_width_vec: Vector3 = ---;
    // get_axes(axes_a, *plane_a_normal, *plane_a_height_vec, *plane_a_width_vec);   

    // pt_on_infinite_plane := project_point_onto_plane(position_b, position_a, plane_a_normal);
    // diff_to_pt_on_infinite_plane := pt_on_infinite_plane - position_a;

    // clamped_width_dist := clamp(dot(diff_to_pt_on_infinite_plane, plane_a_width_vec), -plane_a.width*0.5, plane_a.width*0.5);
    // clamped_height_dist := clamp(dot(diff_to_pt_on_infinite_plane, plane_a_height_vec), -plane_a.half_height, plane_a.half_height);
    // clamped_pt_on_plane := position_a + plane_a_width_vec * clamped_width_dist + plane_a_height_vec * clamped_height_dist;
    
    // diff_to_clamped_pt := clamped_pt_on_plane - position_b;
    // return abs(diff_to_clamped_pt.x) < box_b.width * 0.5
    //     && abs(diff_to_clamped_pt.y) < box_b.length * 0.5
    //     && abs(diff_to_clamped_pt.z) < box_b.half_height;
    return false;
}

// ------------------------------------------------------------------------------------------------------- box

is_overlap_box_sphere :: inline (collider_a: Collision_Shape, position_a: Vector3, axes_a: Axes, collider_b: Collision_Shape, position_b: Vector3, axes_b: Axes) -> bool {
    return is_overlap_sphere_box(collider_b, position_b, axes_b, collider_a, position_a, axes_a);
}

is_overlap_box_capsule :: inline (collider_a: Collision_Shape, position_a: Vector3, axes_a: Axes, collider_b: Collision_Shape, position_b: Vector3, axes_b: Axes) -> bool {
    return is_overlap_capsule_box(collider_b, position_b, axes_b, collider_a, position_a, axes_a);
}

is_overlap_box_rect :: inline (collider_a: Collision_Shape, position_a: Vector3, axes_a: Axes, collider_b: Collision_Shape, position_b: Vector3, axes_b: Axes) -> bool {
    return is_overlap_rect_box(collider_b, position_b, axes_b, collider_a, position_a, axes_a);
}

is_overlap_box_box :: (collider_a: Collision_Shape, position_a: Vector3, axes_a: Axes, collider_b: Collision_Shape, position_b: Vector3, axes_b: Axes) -> bool {
    // box_a := *collider_a.box;
    // box_b := *collider_b.box;

    // // fore, up, right
    // box_a_axes: [3]Vector3 = ---;
    // get_axes(axes_a, *box_a_axes[0], *box_a_axes[1], *box_a_axes[2]);

    // box_b_axes: [3]Vector3 = ---;
    // get_axes(axes_b, *box_b_axes[0], *box_b_axes[1], *box_b_axes[2]);

    // // from Real Time Collision Detection, Christer Ericson 

    // // separating axis theorem: for two convex hulls, if they don't overlap, there must be a plane separating them. in other words, projections along the normal of that plane will be non-overlapping.

    // t := position_b - position_a;
    // b_rel_pos := Vector3.{dot(t, box_a_axes[0]), dot(t, box_a_axes[1]), dot(t, box_a_axes[2])};

    // ERROR :: SMALL_NUMBER;
    // // b's rotation relative to a
    // b_rel_rot: Matrix3 = ---;
    // abs_b_rel_rot: Matrix3 = ---;

    // for i : 0..2 {
    //     for j : 0..2 {
    //         b_rel_rot.coef[i][j] = dot(box_a_axes[i], box_b_axes[j]);
    //         // ERROR is added to account for errors where two edges are nearly parallel, and so their cross product is near zero
    //         abs_b_rel_rot.coef[i][j] = abs(b_rel_rot.coef[i][j]) + ERROR;
    //     }
    //     // test for separation along a's axes
    //     a_extent_along_axis := box_a.extent.component[i];
    //     b_extent_along_axis := 
    //           box_b.extent.x * abs_b_rel_rot.coef[i][0] 
    //         + box_b.extent.y * abs_b_rel_rot.coef[i][1] 
    //         + box_b.extent.z * abs_b_rel_rot.coef[i][2];
    //     distance := abs(b_rel_pos.component[i]);
    //     if distance > a_extent_along_axis + b_extent_along_axis then return false;
    // }

    // for 0..2 {
    //     // test for separation along b's axes
    //     a_extent_along_axis := 
    //           box_a.extent.x * abs_b_rel_rot.coef[0][it] 
    //         + box_a.extent.y * abs_b_rel_rot.coef[1][it] 
    //         + box_a.extent.z * abs_b_rel_rot.coef[2][it];
    //     b_extent_along_axis := box_b.extent.component[it];
    //     distance := abs(
    //           b_rel_pos.x * b_rel_rot.coef[0][it] 
    //         + b_rel_pos.y * b_rel_rot.coef[1][it] 
    //         + b_rel_pos.z * b_rel_rot.coef[2][it]
    //     );
    //     if distance > a_extent_along_axis + b_extent_along_axis then return false;
    // }

    // // test for separation along axes orthogonal to edge pairs between the boxes

    // test_axis_orthogonal_to_edge_pair :: (a_0: s32, a_coef_0: s32, a_coef_1: s32, b_0: s32, b_coef_0: s32, b_coef_1: s32, $same_order: bool) #expand {
    //     // a's second trio of values swaps the first and second from the first trio
    //     a_1 := a_coef_0;
    //     a_coef_2 := a_0;
    //     a_coef_3 := a_coef_1;
    //     // b's second trio of values swaps the first and third from the first trio
    //     b_1 := b_coef_1;
    //     b_coef_2 := b_coef_0;
    //     b_coef_3 := b_0;

    //     a_extent_along_axis := 
    //           `box_a.extent.component[a_0] * `abs_b_rel_rot.coef[a_coef_0][a_coef_1] 
    //         + `box_a.extent.component[a_1] * `abs_b_rel_rot.coef[a_coef_2][a_coef_3];
    //     b_extent_along_axis := 
    //           `box_b.extent.component[b_0] * `abs_b_rel_rot.coef[b_coef_0][b_coef_1] 
    //         + `box_b.extent.component[b_1] * `abs_b_rel_rot.coef[b_coef_2][b_coef_3];
    //     #if same_order {
    //         distance := abs(
    //               `b_rel_pos.component[a_0] * `b_rel_rot.coef[a_coef_0][a_coef_1] 
    //             - `b_rel_pos.component[a_1] * `b_rel_rot.coef[a_coef_2][a_coef_3]
    //         );
    //     } else {
    //         distance := abs(
    //               `b_rel_pos.component[a_1] * `b_rel_rot.coef[a_coef_2][a_coef_3] 
    //             - `b_rel_pos.component[a_0] * `b_rel_rot.coef[a_coef_0][a_coef_1]
    //         );
    //     }
    //     if distance > a_extent_along_axis + b_extent_along_axis then `return false;
    // } 

    // // ax, bx
    // test_axis_orthogonal_to_edge_pair(
    //     1, 2, 0,
    //     1, 0, 2,
    //     false
    // );
    // // ax, by
    // test_axis_orthogonal_to_edge_pair(
    //     1, 2, 1,
    //     0, 0, 2,
    //     false
    // );
    // // ax, bz
    // test_axis_orthogonal_to_edge_pair(
    //     1, 2, 2,
    //     0, 0, 1,
    //     false
    // );
    // // ay, bx
    // test_axis_orthogonal_to_edge_pair(
    //     0, 2, 0,
    //     1, 1, 2,
    //     true
    // );
    // // ay, by
    // test_axis_orthogonal_to_edge_pair(
    //     0, 2, 1,
    //     0, 1, 2,
    //     true
    // );
    // // ay, bz
    // test_axis_orthogonal_to_edge_pair(
    //     0, 2, 2,
    //     0, 1, 1,
    //     true
    // );
    // // az, bx
    // test_axis_orthogonal_to_edge_pair(
    //     0, 1, 0,
    //     1, 2, 2,
    //     false
    // );
    // // az, by
    // test_axis_orthogonal_to_edge_pair(
    //     0, 1, 1,
    //     0, 2, 2,
    //     false
    // );
    // // az, bz
    // test_axis_orthogonal_to_edge_pair(
    //     0, 1, 2,
    //     0, 2, 1,
    //     false
    // );

    // return true;
    return false;
}

is_overlap_box_aabb :: inline (collider_a: Collision_Shape, position_a: Vector3, axes_a: Axes, collider_b: Collision_Shape, position_b: Vector3, axes_b: Axes) -> bool {
    return is_overlap_box_box(collider_b, position_b, axes_b, collider_a, position_a, axes_a, QUATERNION_IDENTITY);
}

is_overlap_box_half_space :: inline (collider_a: Collision_Shape, position_a: Vector3, axes_a: Axes, collider_b: Collision_Shape, position_b: Vector3, axes_b: Axes) -> bool {
    // box_a := *collider_a.box;

    // box_fore, box_up, box_right: Vector3 = ---;
    // get_axes(axes_a, *box_fore, *box_up, *box_right);

    // plane_normal := fore_direction(*axes_b);

    // projected_radius := 
    //       box_a.half_width * abs(dot(plane_normal, box_right))
    //     + box_a.half_length * abs(dot(plane_normal, box_fore))
    //     + box_a.half_height * abs(dot(plane_normal, box_up));

    // _, signed_box_center_dist := project_point_onto_plane(position_a, position_b, plane_normal);
    // return signed_box_center_dist < projected_radius;
    return false;
}

// ------------------------------------------------------------------------------------------------------- aabb

is_overlap_aabb_sphere :: inline (collider_a: Collision_Shape, position_a: Vector3, axes_a: Axes, collider_b: Collision_Shape, position_b: Vector3, axes_b: Axes) -> bool {
    return is_overlap_sphere_aabb(collider_b, position_b, axes_b, collider_a, position_a, axes_a);
}

is_overlap_aabb_capsule :: inline (collider_a: Collision_Shape, position_a: Vector3, axes_a: Axes, collider_b: Collision_Shape, position_b: Vector3, axes_b: Axes) -> bool {
    return is_overlap_capsule_aabb(collider_b, position_b, axes_b, collider_a, position_a, axes_a);
}

is_overlap_aabb_rect :: inline (collider_a: Collision_Shape, position_a: Vector3, axes_a: Axes, collider_b: Collision_Shape, position_b: Vector3, axes_b: Axes) -> bool {
    return is_overlap_rect_aabb(collider_b, position_b, axes_b, collider_a, position_a, axes_a);
}

is_overlap_aabb_box :: inline (collider_a: Collision_Shape, position_a: Vector3, axes_a: Axes, collider_b: Collision_Shape, position_b: Vector3, axes_b: Axes) -> bool {
    return is_overlap_box_box(collider_b, position_b, QUATERNION_IDENTITY, collider_a, position_a, axes_a);
}

is_overlap_aabb_aabb :: (collider_a: Collision_Shape, position_a: Vector3, axes_a: Axes, collider_b: Collision_Shape, position_b: Vector3, axes_b: Axes) -> bool {
    aabb_a := *collider_a.aabb;
    aabb_b := *collider_b.aabb;
    abs_pos_diff := abs(position_a - position_b);
    return abs_pos_diff.x < aabb_a.half_width + aabb_b.half_width
        && abs_pos_diff.y < aabb_a.half_length + aabb_b.half_length
        && abs_pos_diff.z < aabb_a.half_height + aabb_b.half_height;
}

is_overlap_aabb_half_space :: inline (collider_a: Collision_Shape, position_a: Vector3, axes_a: Axes, collider_b: Collision_Shape, position_b: Vector3, axes_b: Axes) -> bool {
    // box_a := *collider_a.box;

    // plane_normal := fore_direction(*axes_b);

    // projected_radius := 
    //       box_a.half_width * abs(plane_normal.x)
    //     + box_a.half_length * abs(plane_normal.y)
    //     + box_a.half_height * abs(plane_normal.z);

    // _, signed_box_center_dist := project_point_onto_plane(position_a, position_b, plane_normal);
    // return signed_box_center_dist < projected_radius;
    return false;
}

// is_overlap_box_box_my_take :: (collider_a: Collision_Shape, position_a: Vector3, axes_a: Axes, collider_b: Collision_Shape, position_b: Vector3, axes_b: Axes) -> bool {
//     box_a := *collider_a.box;
//     box_b := *collider_b.box;

//     box_a_fore, box_a_up, box_a_right: Vector3 = ---;
//     get_axes(axes_a, *box_a_fore, *box_a_up, *box_a_right);

//     box_b_fore, box_b_up, box_b_right: Vector3 = ---;
//     get_axes(axes_b, *box_b_fore, *box_b_up, *box_b_right);

//     // populate normals for separating axis test
//     // separating axis theorem: for two convex hulls, if they don't overlap, there must be a plane separating them. in other words, projections along the normal of that plane will be non-overlapping.
//     separating_axis_normals: [15]Vector3 = ---;
//     separating_axis_normals[0]  = box_a_fore;
//     separating_axis_normals[1]  = box_a_up;
//     separating_axis_normals[2]  = box_a_right;
//     separating_axis_normals[3]  = box_b_fore;
//     separating_axis_normals[4]  = box_b_up;
//     separating_axis_normals[5]  = box_b_right;
//     n := 6;
//     for i : 0..2 {
//         for j : 3..5 {
//             scaled_sin_t_vec := cross(separating_axis_normals[i], separating_axis_normals[j]);
//             if length_squared(scaled_sin_t_vec) < VERY_SMALL_NUMBER {
//                 // the normals are (roughly) parallel (and so on the same plane)
//                 // use another vec from the j pool to get the normal of the plane the j vec is on, but the i vec may not be
//                 j2 := increment_wrap(j, 3, 5); 
//                 normal := cross(separating_axis_normals[i], separating_axis_normals[j2]);
//                 scaled_sin_t_vec = cross(separating_axis_normals[i], normal);
//             }
//             separating_axis_normals[n] = scaled_sin_t_vec;
//             n += 1;
//         }
//     }

//     points_a: [8]Vector3;
//     points_b: [8]Vector3;
//     get_box_points(position_a, box_a_fore * box_a.half_length, box_a_up * box_a.half_height, box_a_right * box_a.half_width, *points_a);
//     get_box_points(position_b, box_b_fore * box_b.half_length, box_b_up * box_b.half_height, box_b_right * box_b.half_width, *points_b);

//     min_projection_a :=  FLOAT32_MAX;
//     max_projection_a := -FLOAT32_MAX;
//     min_projection_b :=  FLOAT32_MAX;
//     max_projection_b := -FLOAT32_MAX;

//     for sa_normal : separating_axis_normals {
//         if length_squared(sa_normal) < VERY_SMALL_NUMBER then continue;

//         for points_a {
//             projection_a := dot(points_a[it_index], sa_normal);
//             projection_b := dot(points_b[it_index], sa_normal);
//             if it_index == 0 {
//                 min_projection_a = projection_a;
//                 max_projection_a = projection_a;
//                 min_projection_b = projection_b;
//                 max_projection_b = projection_b;
//             } else {
//                 min_projection_a = min(projection_a, min_projection_a);
//                 max_projection_a = max(projection_a, max_projection_a);
//                 min_projection_b = min(projection_b, min_projection_b);
//                 max_projection_b = max(projection_b, max_projection_b);
//             }
//         }

//         if !ordered_ranges_overlap(Vector2.{min_projection_a, max_projection_a}, Vector2.{min_projection_b, max_projection_b}) {
//             return false;
//         }
//     }

//     return true;
// }