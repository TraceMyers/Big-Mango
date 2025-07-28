procedure_capture_data: Procedure_Capture_Data;

Procedure_Capture_Type :: struct {

	solve_potential_contact_sphere_rect :: struct {
		sphere_a: *Sphere_Shape;
		rect_b: *Rect_Shape;
		contact_radius: float32;
		contact_radius_sq: float32;
		sphere_a_sweep_diff: Vector3;
		sphere_a_sweep_begin: Vector3;
		sphere_a_sweep_end: Vector3;
		rect_b_normal: Vector3;
		rect_b_axis_up: Vector3;
		rect_b_axis_right: Vector3;
		sweep_begin_projected_to_rect: Vector3;
		current_diff: Vector3;
		current_dist_signed: float32;
		current_dist: float32;
		sweep_signed_dist_along_normal: float32;
		sweep_dist_sq: float32;
		sweep_begin_projected_to_plane: Vector3;
		signed_dist_to_plane_projection: float;
		dist_to_plane_projection: float32;
		sweep_dist_along_normal: float32;
		buffered_dist_to_plane_projection: float32;
		sphere_location_at_point_of_contact: Vector3;
		b_world_space_contact_point: Vector3;
	}

	solve_potential_contact_sphere_sphere :: struct {
		sphere_a: *Sphere_Shape;
		sphere_b: *Sphere_Shape;
		contact_radius: float32;
		contact_radius_sq: float32;
		current_diff: Vector3;
		current_dist_sq: float32;
		contact_dist: float32;
		sphere_a_sweep_diff: Vector3;
		sphere_a_sweep_begin: Vector3;
		sphere_a_sweep_end: Vector3;
		b_closest_pt_on_line: Vector3;
		norm_dist_along_sweep: float;
		dist_sq_from_line: float32;
		clamped_norm_dist_along_sweep: float32;
		b_closest_pt_on_sweep: Vector3;
		dist_sq_from_sweep: float32;
		move_from_line_projection_dist: float32;
		sphere_a_sweep_length_sq: float32;
		move_from_line_projection_norm_dist: float;
		sphere_a_sweep_length: float32;
		normal_sign: float32;
		norm_time: float32;
		a_contact_position: Vector3;
		contact_diff: Vector3;
		is_contact: bool;
	}

}

Procedure_Capture_Data :: struct {
	solve_potential_contact_sphere_rect: Procedure_Capture_Type.solve_potential_contact_sphere_rect;
	solve_potential_contact_sphere_sphere: Procedure_Capture_Type.solve_potential_contact_sphere_sphere;
}

Procedure_Capture_Duplicate :: struct {

	solve_potential_contact_sphere_rect :: (body_a: Collision_Body, axes_a: Axes, body_b: Collision_Body, axes_b: Axes, time_step: float, out_result: *Contact_Result) -> bool {
		using procedure_capture_data.solve_potential_contact_sphere_rect;
	    sphere_a    = *body_a.shape.sphere;
	    rect_b      = *body_b.shape.rect;
	
	    contact_radius = sphere_a.radius;
	    contact_radius_sq = square(contact_radius);
	    if contact_radius < VERY_SMALL_NUMBER {
	        out_result.norm_time = 1;
	        return false;
	    }
	
	    sphere_a_sweep_diff         = body_a.velocity * time_step;
	    sphere_a_sweep_begin        = body_a.center;
	    sphere_a_sweep_end          = body_a.center + sphere_a_sweep_diff;
	
	    rect_b_normal       = axes_b.fore;
	    rect_b_axis_up      = axes_b.up;
	    rect_b_axis_right   = axes_b.right;
	
	    sweep_begin_projected_to_rect = clamp_point_to_rect(sphere_a_sweep_begin, body_b.center, rect_b_axis_up, rect_b_axis_right, rect_b.half_height, rect_b.half_width);
	
	    current_diff        = sphere_a_sweep_begin - sweep_begin_projected_to_rect;
	    current_dist_signed = dot(rect_b_normal, current_diff);
	
	    // if the sphere is behind the rect and will stay behind it, there is no collision
	    if current_dist_signed < 0 {
	        out_result.norm_time = 1;
	        return false;
	    }
	
	    current_dist = current_dist_signed;
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
	    sweep_signed_dist_along_normal = dot(sphere_a_sweep_diff, rect_b_normal);
	    if sweep_signed_dist_along_normal >= 0 {
	        out_result.norm_time = 1;
	        return false;
	    }
	
	    sweep_dist_sq = length_squared(sphere_a_sweep_diff);
	    // we don't have a contact at = 0 and we're only moving imperceptibly if at all, so no contact
	    if sweep_dist_sq < VERY_SMALL_NUMBER {
	        out_result.norm_time = 1;
	        return false;
	    }
	
	    // reprojection is needed here for raycasting. we don't know that the point on the rect wasn't clamped
	    // it seems wasteful to project to the plane after projecting to the rect... but actually zero instructions are saved when doing it in reverse as far as I can tell.
	    sweep_begin_projected_to_plane, signed_dist_to_plane_projection = project_point_onto_plane(body_a.center, body_b.center, rect_b_normal);
	    dist_to_plane_projection = abs(signed_dist_to_plane_projection);
	
	    // the ratio of the line intersection's sidelength to the segment's sidelength can be used to scale the segment difference so as to represent the ray intersection hypotenuse minus the distance s.t. the sphere is touching the rect rather than its center being on the rect (without any normalization / sqrt)
	    sweep_dist_along_normal = -sweep_signed_dist_along_normal;
	    buffered_dist_to_plane_projection = dist_to_plane_projection - contact_radius;
	    out_result.norm_time = buffered_dist_to_plane_projection / sweep_dist_along_normal;
	
	    if out_result.norm_time <= 0 || out_result.norm_time >= 1 {
	        out_result.norm_time = 1;
	        return false;
	    }
	
	    sphere_location_at_point_of_contact = sphere_a_sweep_begin + sphere_a_sweep_diff * out_result.norm_time;
	    out_result.a_local_space_contact_point = -out_result.contact_normal * sphere_a.radius;
	    b_world_space_contact_point = sphere_location_at_point_of_contact + out_result.a_local_space_contact_point;
	    out_result.b_local_space_contact_point = world_space_to_local_space(b_world_space_contact_point - body_b.center, rect_b_normal, rect_b_axis_up, rect_b_axis_right);
	
	    return true;
	} @struct_capture_duplicate 
	
	solve_potential_contact_sphere_sphere :: (body_a: Collision_Body, axes_a: Axes, body_b: Collision_Body, axes_b: Axes, time_step: float, out_result: *Contact_Result) -> bool {
		using procedure_capture_data.solve_potential_contact_sphere_sphere;
	    sphere_a = *body_a.shape.sphere;
	    sphere_b = *body_b.shape.sphere;
	
	    contact_radius = sphere_a.radius + sphere_b.radius;
	    contact_radius_sq = square(contact_radius);
	    if contact_radius < VERY_SMALL_NUMBER {
	        out_result.norm_time = 1;
	        return false;
	    }
	
	    // solve t = 0 contacts.
	    current_diff = body_a.center - body_b.center;
	    current_dist_sq = length_squared(current_diff);
	    if current_dist_sq < contact_radius_sq {
	        out_result.norm_time = 0;
	        if current_dist_sq < VERY_SMALL_NUMBER {
	            // colliders are two close to calculate a normal. just need to pick something
	            out_result.contact_normal = .{x=1};
	            out_result.contact_depth_if_time_is_zero = max(sphere_a.radius, sphere_b.radius);
	        } else {
	            contact_dist = sqrt(current_dist_sq);
	            out_result.contact_normal = current_diff / contact_dist;
	            out_result.contact_depth_if_time_is_zero = contact_radius - contact_dist;
	        }
	        out_result.a_local_space_contact_point = -out_result.contact_normal * sphere_a.radius;
	        out_result.b_local_space_contact_point =  out_result.contact_normal * sphere_b.radius;
	        return true;
	    }
	
	    sphere_a_sweep_diff         = body_a.velocity * time_step;
	    sphere_a_sweep_begin        = body_a.center;
	    sphere_a_sweep_end          = body_a.center + sphere_a_sweep_diff;
	
	    b_closest_pt_on_line, norm_dist_along_sweep = closest_point_on_line(*body_b.center, *sphere_a_sweep_begin, *sphere_a_sweep_end);
	
	    dist_sq_from_line = distance_squared(b_closest_pt_on_line, body_b.center);
	    if dist_sq_from_line >= contact_radius_sq {
	        out_result.norm_time = 1.0;
	        return false;
	    }
	
	    clamped_norm_dist_along_sweep = clamp(norm_dist_along_sweep, 0, 1);
	    b_closest_pt_on_sweep = sphere_a_sweep_begin + sphere_a_sweep_diff * clamped_norm_dist_along_sweep;
	    dist_sq_from_sweep = distance_squared(b_closest_pt_on_sweep, body_b.center);
	    if dist_sq_from_sweep >= contact_radius_sq {
	        out_result.norm_time = 1.0;
	        return false;
	    }
	
	    move_from_line_projection_dist      = sqrt(contact_radius_sq - dist_sq_from_line);
	    sphere_a_sweep_length_sq            = length_squared(sphere_a_sweep_diff);
	
	    if sphere_a_sweep_length_sq < VERY_SMALL_NUMBER {
	        move_from_line_projection_norm_dist = 0;
	    } else {
	        sphere_a_sweep_length = sqrt(sphere_a_sweep_length_sq);
	        move_from_line_projection_norm_dist = move_from_line_projection_dist / sphere_a_sweep_length;
	    }
	
	    normal_sign         = -sign(clamped_norm_dist_along_sweep);
	    norm_time           = norm_dist_along_sweep + normal_sign * move_from_line_projection_norm_dist;
	    a_contact_position  = sphere_a_sweep_begin + body_a.velocity * out_result.norm_time;
	    contact_diff        = a_contact_position - body_b.center;
	
	    out_result.contact_normal = normalize(contact_diff);
	    is_contact = true;
	    if norm_time >= 1 {
	        out_result.norm_time = 1;
	        is_contact = false;
	    }
	
	    // for spheres, just ignore the axes and use world axes
	    out_result.a_local_space_contact_point = -out_result.contact_normal * sphere_a.radius;
	    out_result.b_local_space_contact_point =  out_result.contact_normal * sphere_b.radius;
	
	    return is_contact;
	} @struct_capture_duplicate
	
}