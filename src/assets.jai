OBJ_FINALBASEMESH :: Asset_Reference.{"meshes/FinalBaseMesh.obj", 16640641787251094692};
MESH_FINALBASEMESH :: Asset_Reference.{"mesh_loaders/finalbasemesh.mesh", 4174510268234168814};
MESH_CUBE :: Asset_Reference.{"mesh_loaders/primitives/cube.mesh", 13466508853721018356};
MESH_PLANE :: Asset_Reference.{"mesh_loaders/primitives/plane.mesh", 5025412497311977439};
MESH_SPHERE_HIGH_POLY :: Asset_Reference.{"mesh_loaders/primitives/sphere_high_poly.mesh", 9498632380246332172};
MESH_SPHERE_LOW_POLY :: Asset_Reference.{"mesh_loaders/primitives/sphere_low_poly.mesh", 8623116171707731123};
MESH_SPHERE_MID_POLY :: Asset_Reference.{"mesh_loaders/primitives/sphere_mid_poly.mesh", 27975126169823819};

OBJ_ASSET_REFERENCES: [1]*Asset_Reference;
load_obj_asset_reference_pointers :: () {
	OBJ_ASSET_REFERENCES[0] = *OBJ_FINALBASEMESH;
}

MESH_ASSET_REFERENCES: [6]*Asset_Reference;
load_mesh_asset_reference_pointers :: () {
	MESH_ASSET_REFERENCES[0] = *MESH_FINALBASEMESH;
	MESH_ASSET_REFERENCES[1] = *MESH_CUBE;
	MESH_ASSET_REFERENCES[2] = *MESH_PLANE;
	MESH_ASSET_REFERENCES[3] = *MESH_SPHERE_HIGH_POLY;
	MESH_ASSET_REFERENCES[4] = *MESH_SPHERE_LOW_POLY;
	MESH_ASSET_REFERENCES[5] = *MESH_SPHERE_MID_POLY;
}
