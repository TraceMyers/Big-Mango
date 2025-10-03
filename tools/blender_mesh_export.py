import bpy
import bmesh
import mathutils
import struct
from typing import (
	List,
	Dict,
	Tuple
)
from bpy.props import (
	StringProperty,
	BoolProperty,
	FloatProperty
)
from bpy_extras.io_utils import (
	ExportHelper,
	orientation_helper,
	axis_conversion
)


class Vertex:
	def __init__(self, position: Tuple[float, float, float], normal: Tuple[float, float, float], joint_ids : Tuple[int, int, int, int], weights : Tuple[float, float, float]):
		self.position = position
		self.normal = normal
		self.joint_ids = joint_ids
		self.weights = weights


class Mesh:
	def __init__(self):
		self.name_to_joint_id : Dict[str, int] = {}
		self.joints : List[bpy.types.Bone] = []
		self.verts : List[Vertex] = []
		self.tris : List[Tuple[int, int, int]] = []

	@staticmethod
	def from_mesh_and_armature(blender_obj : bpy.types.Object, blender_mesh : bpy.types.Mesh, blender_armature : bpy.types.Armature):
		# ---

		def append_armature_hierarchy(joints : List[bpy.types.Bone], bone : bpy.types.Bone):
			joints.append(bone)
			for child in bone.children:
				if child.use_deform:
					append_armature_hierarchy(joints, child)

		def groups_to_tuple4(a):
			if len (a) == 0:
				return -1, -1, -1, -1
			elif len (a) == 1:
				return a[0], -1, -1, -1
			elif len (a) == 2:
				return a[0], a[1], -1, -1
			elif len (a) == 3:
				return a[0], a[1], a[2], -1
			return a[0], a[1], a[2], a[3]

		def weights_to_tuple3(a):
			if len (a) == 0:
				return 0, 0, 0
			elif len (a) == 1:
				return round (a[0], 6), 0, 0
			elif len (a) == 2:
				return round (a[0], 6), round (a[1], 6), 0
			return round (a[0], 6), round (a[1], 6), round (a[2], 6)

		# ---

		result = Mesh()

		# if it's a skinned mesh, pull out the skeleton
		if blender_armature is not None:
			root = None
			for b in blender_armature.bones:
				if b.parent is None and b.use_deform:
					if root is not None:
						raise Exception("found multiple root bones in armature")
					root = b
			if root is None:
				raise Exception("found no root bones in armature")
			
			append_armature_hierarchy(result.joints, root)
			signed_16bit_max = 0x7fff
			if len(result.joints) > signed_16bit_max:
				raise Exception(f"armature has {len(result.joints)} joints, which is greater than the max: {signed_16bit_max}")
			for i, b in enumerate (result.joints):
				result.name_to_joint_id.update({b.name : i})

		# get mesh data
		vert_group_names = {g.index : g.name for g in blender_obj.vertex_groups}
		vertices_dict = {}
		for i, poly in enumerate(blender_mesh.polygons):
			if len(poly.vertices) != 3:
				raise Exception(f"found a face with {len(poly.vertices)} vertices. mesh faces must all be triangles.")
			tri = []
			for j, vert_index in enumerate(poly.vertices):
				if vert_index in vertices_dict:
					result_vert_index = vertices_dict[vert_index]
				else:
					result_vert_index = len(result.verts)
					vertices_dict.update({vert_index : result_vert_index})
					vert = blender_mesh.vertices[vert_index]
					if len(vert.groups) != 0 and blender_armature is None:
						raise Exception("Mesh has vertices assigned to vertex groups, but we could not find an armature associated with it. Make sure it is parented to an armature, or it has a valid skin modifier.")
					if len (vert.groups) > 4:
						raise Exception(f"Vertex {vert_index} has more than 4 groups assigned to it.")
					groups = groups_to_tuple4([g.group for g in vert.groups])
					weights = weights_to_tuple3([g.weight for g in vert.groups])
					joint_ids = [-1 for i in range (len (groups))]
					for i in range (len (groups)):
						if groups[i] != -1:
							name = vert_group_names[groups[i]]
							if name not in result.name_to_joint_id:
								raise Exception (f"Vertex is assigned to group {name} but we could not find a deform bone with this name in the armature.")
							joint_ids[i] = result.name_to_joint_id[name]
					result.verts.append(Vertex(
						tuple(vert.co),
						tuple(vert.normal),
						tuple(joint_ids),
						weights
					))
				tri.append(result_vert_index)
			result.tris.append((tri[0], tri[1], tri[2]))
			
		return result


	def write_binary(self, filename: str):
		# ---

		def remainder_of_4_byte_alignment(val):
			return 4 - (val % 4)

		# ---

		with open(filename, "wb") as file:
			fw = file.write
			fw(b"mgo : skinned mesh : version 1\n")
			fw(b"joints : %u\n" % len(self.joints))
			fw(b"vertices : %u\n" % len(self.verts))
			fw(b"triangles : %u\n" % len(self.tris))

			# aligning to 4 bytes just to be consistent about the rule that non-text number values are aligned properly (the next written value will be a 4 byte unsigned int)
			file_pos = file.tell()
			align_to_4_bytes_remainder_a = remainder_of_4_byte_alignment(file_pos)
			for b in range(align_to_4_bytes_remainder_a):
				fw(b"\xff")
			file_pos += align_to_4_bytes_remainder_a

			file_pos += 4 # simulate having already written the next integer value
			file_pos += 1 # simulate writing a newline
			joints_name_section_length = sum(len(joint.name.encode("utf-8")) + 1 for joint in self.joints) # +1 is for newlines
			number_data_begin = file_pos + joints_name_section_length
			align_to_4_bytes_remainder_b = remainder_of_4_byte_alignment(number_data_begin)
			corruption_sentinel_size = 4
			number_data_begin += align_to_4_bytes_remainder_b + corruption_sentinel_size

			fw(struct.pack("<I", number_data_begin))
			fw(b"\n")

			for joint in self.joints:
				fw(b"%s\n" % bytes(joint.name, 'UTF-8'))

			# aligning to 4 bytes for potentially faster read of all following 4 byte number values
			for b in range(align_to_4_bytes_remainder_b):
				fw(b"\xff")
			
			# 4 bytes of zeroes as a simple corruption sentinel or read algorithm validation
			fw(b"\xff\xff\xff\xff")

			true_number_data_begin = file.tell()
			if true_number_data_begin != number_data_begin:
				raise Exception(f"expected number data to begin at {number_data_begin}, but it is beginning at {true_number_data_begin}")

			for joint in self.joints:
				if joint.parent is not None:
					local_transform = joint.parent.matrix_local.inverted() @ joint.matrix_local # what is this?
				else:
					local_transform = joint.matrix_local
				fw(struct.pack("<4f", local_transform[0][0], local_transform[0][1], local_transform[0][2], local_transform[0][3]))
				fw(struct.pack("<4f", local_transform[1][0], local_transform[1][1], local_transform[1][2], local_transform[1][3]))
				fw(struct.pack("<4f", local_transform[2][0], local_transform[2][1], local_transform[2][2], local_transform[2][3]))
				fw(struct.pack("<4f", local_transform[3][0], local_transform[3][1], local_transform[3][2], local_transform[3][3]))

			for joint in self.joints:
				if joint.parent is not None:
					fw(struct.pack("<h", self.name_to_joint_id[joint.parent.name]))
				else:
					fw(struct.pack("<h", -1))
			
			joint_parents_end = file.tell()
			align_to_4_bytes_remainder = remainder_of_4_byte_alignment(joint_parents_end)
			for b in range(align_to_4_bytes_remainder):
				fw(b"\xff")

			for vert in self.verts:
				fw(struct.pack("<3f", vert.position[0], vert.position[1], vert.position[2]))
				fw(struct.pack("<3f", vert.normal[0], vert.normal[1], vert.normal[2]))
				fw(struct.pack("<3f", vert.weights[0], vert.weights[1], vert.weights[2]))
				fw(struct.pack("<4h", vert.joint_ids[0], vert.joint_ids[1], vert.joint_ids[2], vert.joint_ids[3]))

			for tri in self.tris:
				fw(struct.pack("<3I", tri[0], tri[1], tri[2]))


def export_meshes (
	context : bpy.types.Context,
	filename : str,
	use_selection : bool,
	apply_transform : bool,
	axis_conversion_matrix : mathutils.Matrix
):
	import os

	if bpy.ops.object.mode_set.poll():
		bpy.ops.object.mode_set(mode = 'OBJECT')
	if use_selection:
		objs = context.selected_objects
	else:
		objs = context.scene.objects
	for obj in objs:
		try:
			me = obj.to_mesh()
		except RuntimeError:
			continue
		armature_obj = obj.find_armature()
		armature = None
		if armature_obj is not None:
			armature = armature_obj.data.copy()
		# Apply object transform and calculate normals
		if apply_transform:
			me.transform(obj.matrix_world)
			if armature is not None:
				armature.transform(obj.matrix_world)
		if axis_conversion_matrix is not None:
			me.transform(axis_conversion_matrix.to_4x4())
			if armature is not None:
				armature.transform (axis_conversion_matrix.to_4x4())
		# me.calc_normals()
		# Triangulate mesh
		bm = bmesh.new()
		bm.from_mesh(me)
		bmesh.ops.triangulate(bm, faces = bm.faces[:])
		bm.to_mesh(me)
		bm.free()

		result = Mesh.from_mesh_and_armature(obj, me, armature)
		output_filename = os.path.join(os.path.dirname(filename), obj.name) + Exporter.filename_ext
		result.write_binary(output_filename)
		obj.to_mesh_clear()
		print(f"Exported mesh {obj.name} to file {output_filename}.\n")


@orientation_helper(axis_forward = '-Z', axis_up = 'Y')
class Exporter(bpy.types.Operator, ExportHelper):
	"""Export mesh data"""
	bl_idname = "export.anim_example_mesh"
	bl_label = "Export mesh with skinning (.mgosm)"
	bl_options = { 'REGISTER', 'UNDO' }
	filename_ext = ".mgosm"

	use_selection : BoolProperty (
		name = "Only Selected",
		description = "Export only the selected meshes.",
		default = True
	)
	apply_transform : BoolProperty (
		name = "Apply object transform",
		description = "Apply the object transform matrix when exporting meshes.",
		default = True
	)

	def execute (self, context : bpy.types.Context):
		context.window.cursor_set ('WAIT')
		export_meshes (
			context,
			self.filepath,
			self.use_selection,
			self.apply_transform,
			axis_conversion (to_forward = self.axis_forward, to_up = self.axis_up)
		)
		context.window.cursor_set ('DEFAULT')

		return { 'FINISHED' }


def export_menu_func(self, context : bpy.types.Context):
	self.layout.operator(Exporter.bl_idname)


def register():
    bpy.utils.register_class(Exporter)
    bpy.types.TOPBAR_MT_file_export.append(export_menu_func)


def unregister():
    bpy.utils.unregister_class(Exporter)
    bpy.types.TOPBAR_MT_file_export.remove(export_menu_func)


if __name__ == "__main__":
	register()