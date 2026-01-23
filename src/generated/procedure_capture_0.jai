procedure_capture_data: Procedure_Capture_Data_0;

Procedure_Capture_Type_0 :: struct {

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

Procedure_Capture_Data_0 :: struct {
	solve_potential_contact_sphere_sphere: Procedure_Capture_Type_0.solve_potential_contact_sphere_sphere;
}

Procedure_Capture_Duplicate_0 :: struct {

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
	} @struct_capture_duplicate @CAPTURE_COLLISION_DATA
	
}