procedure_capture_data: Procedure_Capture_Data;

Procedure_Capture_Type :: struct {

	solve_potential_contact_sphere_rect :: struct {
		sphere_a: *Sphere_Shape;
		rect_b: *Rect_Shape;
		center_diff: Vector3;
		distance_along_normal: float32;
		up_dist: float32;
		right_dist: float32;
		a_projected_onto_b: Vector3;
		contact_diff: Vector3;
		dist: float32;
		approach_speed: float32;
		future_dist: float32;
	}

	solve_potential_contact_sphere_sphere :: struct {
		sphere_a: *Sphere_Shape;
		sphere_b: *Sphere_Shape;
		radius_sum: float32;
		diff: Vector3;
		dist_sq: float32;
		dist: float32;
		approach_speed: float32;
		future_dist: float32;
	}

}

Procedure_Capture_Data :: struct {
	solve_potential_contact_sphere_rect: Procedure_Capture_Type.solve_potential_contact_sphere_rect;
	solve_potential_contact_sphere_sphere: Procedure_Capture_Type.solve_potential_contact_sphere_sphere;
}

Procedure_Capture_Duplicate :: struct {

	solve_potential_contact_sphere_rect :: (body_a: Physics_Body, axes_a: Axes, body_b: Physics_Body, axes_b: Axes, time_step: float, out_result: *Contact_Result) -> bool {
		using procedure_capture_data.solve_potential_contact_sphere_rect;
	    sphere_a    = *body_a.shape.sphere;
	    rect_b      = *body_b.shape.rect;
	
	    center_diff = body_a.center - body_b.center;
	    distance_along_normal = dot(center_diff, axes_b.fore);
	    if distance_along_normal < VERY_SMALL_NUMBER {
	        if !rect_b.bidirectional_collision {
	            return false;
	        }
	    }
	
	    up_dist = clamp(dot(center_diff, axes_b.up), -rect_b.half_height, rect_b.half_height);
	    right_dist = clamp(dot(center_diff, axes_b.right), -rect_b.half_width, rect_b.half_width);
	    a_projected_onto_b = body_b.center + axes_b.up * up_dist + axes_b.right * right_dist;
	
	    contact_diff = body_a.center - a_projected_onto_b;
	    dist = distance(body_a.center, a_projected_onto_b);
	
	    out_result.normal = contact_diff / dist;
	
	    approach_speed = dot(out_result.normal, body_b.velocity - body_a.velocity);
	    future_dist = dist - approach_speed * time_step;
	    out_result.depth = sphere_a.radius - future_dist;
	
	    return out_result.depth > 0;
	
	} @struct_capture_duplicate 
	
	solve_potential_contact_sphere_sphere :: (body_a: Physics_Body, axes_a: Axes, body_b: Physics_Body, axes_b: Axes, time_step: float, out_result: *Contact_Result) -> bool {
		using procedure_capture_data.solve_potential_contact_sphere_sphere;
	    sphere_a    = *body_a.shape.sphere;
	    sphere_b    = *body_b.shape.sphere;
	
	    radius_sum = sphere_a.radius + sphere_b.radius;
	    diff = body_a.center - body_b.center;
	    dist_sq = length_squared(diff);
	
	    if dist_sq < VERY_SMALL_NUMBER {
	        out_result.normal = WORLD_RIGHT;
	        out_result.point = body_a.center - out_result.normal * sphere_a.radius;
	        out_result.depth = radius_sum;
	        return true;
	    }
	    
	    dist = sqrt(dist_sq);
	    out_result.normal = diff / dist;
	    out_result.point = body_a.center - out_result.normal * sphere_a.radius;
	
	    approach_speed = dot(out_result.normal, body_b.velocity - body_a.velocity);
	    future_dist = dist - approach_speed * time_step;
	    out_result.depth = radius_sum - future_dist;
	
	    return out_result.depth > 0;
	} @struct_capture_duplicate
	
}