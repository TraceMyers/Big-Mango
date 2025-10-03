// $todo maybe, comptime system: skeleton assets known at compile time, as are their joints. so, do ct lookup
// of the joint, bypassing the runtime lookup.
// joint_index :: ($skeleton_ref: Asset_Reference, $name: string) -> s16 #expand {
//     // look over comptime-known joint names
// }

SKELETON_FILE_SIZE_MAX :: 1024 * 1024;

Skeleton :: struct {
    // this looks like something a degenerate would do because it's true.
    // i did this because it makes loading in the datas faster / simpler. not for cache or anything
    joint_transforms: []Matrix4; 
    joint_inverse_transforms: []Matrix4;
    joint_parents: []s16;
    joint_names: []string;
    joint_hashes: []u32;
    id: s64;
}

Skeleton_Asset :: struct {
    using #as skeleton: Skeleton;
    asset_ref: *Asset_Reference;
}

Skinned_Mesh :: struct {
    using #as mesh: Mesh;
    using #as skeleton: Skeleton;
    vertices: []Mesh_Vertex;
    indices: Index_Buffer;
}

// find_joint :: (skeleton: *Skeleton, name: string) -> *Skeleton.Joint {
//     hash := get_hash(name);
//     skeleton_asset := *skeletons[skeleton.id];
//     for skeleton_asset.joint_hashes {
//         if it == hash {
//             return *skeleton.joints[it_index];
//         }
//     }
//     return null;
// }

save :: #bake_arguments save_or_load_skeleton(rw_mode=.WRITE);
load :: #bake_arguments save_or_load_skeleton(rw_mode=.READ);
save_or_load_skeleton :: (asset_path: string, skeleton: *Skeleton, rw_mode: Rw_Mode, load_allocator := context.allocator) {

}