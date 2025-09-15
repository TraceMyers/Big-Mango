OBJ_FINALBASEMESH :: Asset_Reference.{"meshes/FinalBaseMesh.obj", 16640641787251094692};
OBJ_TREE1 :: Asset_Reference.{"meshes/Tree1.obj", 15848514701592428440};
MESH_FINALBASEMESH :: Asset_Reference.{"mesh_loaders/finalbasemesh.mesh", 4174510268234168814};
MESH_TREE1 :: Asset_Reference.{"mesh_loaders/tree1.mesh", 5896659586971437657};
MESH_CAPSULE_1_6_0_5_0_5 :: Asset_Reference.{"mesh_loaders/primitives/capsule_1_6_0_5_0_5.mesh", 14470429498354650324};
MESH_CUBE :: Asset_Reference.{"mesh_loaders/primitives/cube.mesh", 13466508853721018356};
MESH_PLANE :: Asset_Reference.{"mesh_loaders/primitives/plane.mesh", 5025412497311977439};
MESH_SPHERE_HIGH_POLY :: Asset_Reference.{"mesh_loaders/primitives/sphere_high_poly.mesh", 9498632380246332172};
MESH_SPHERE_LOW_POLY :: Asset_Reference.{"mesh_loaders/primitives/sphere_low_poly.mesh", 8623116171707731123};
MESH_SPHERE_MID_POLY :: Asset_Reference.{"mesh_loaders/primitives/sphere_mid_poly.mesh", 27975126169823819};

OBJ_ASSET_REFERENCES: [2]*Asset_Reference;
load_obj_asset_reference_pointers :: () {
	OBJ_ASSET_REFERENCES[0] = *OBJ_FINALBASEMESH;
	OBJ_ASSET_REFERENCES[1] = *OBJ_TREE1;
}

MESH_ASSET_REFERENCES: [8]*Asset_Reference;
load_mesh_asset_reference_pointers :: () {
	MESH_ASSET_REFERENCES[0] = *MESH_FINALBASEMESH;
	MESH_ASSET_REFERENCES[1] = *MESH_TREE1;
	MESH_ASSET_REFERENCES[2] = *MESH_CAPSULE_1_6_0_5_0_5;
	MESH_ASSET_REFERENCES[3] = *MESH_CUBE;
	MESH_ASSET_REFERENCES[4] = *MESH_PLANE;
	MESH_ASSET_REFERENCES[5] = *MESH_SPHERE_HIGH_POLY;
	MESH_ASSET_REFERENCES[6] = *MESH_SPHERE_LOW_POLY;
	MESH_ASSET_REFERENCES[7] = *MESH_SPHERE_MID_POLY;
}
