import bpy

# Ensure you're in Edit Mode and the object is selected
obj = bpy.context.active_object

# Switch to Object Mode to access data
bpy.ops.object.mode_set(mode='OBJECT')

# Get the mesh data of the object
mesh = obj.data

# Fetch selected faces
selected_faces = [f.index for f in mesh.polygons if f.select]

# Print the corresponding face indices
print("Selected faces indices in the OBJ file:")
for face in selected_faces:
    print(f"Face index: {face}")
    
# Optionally, print corresponding vertex indices for each face
for face in selected_faces:
    vertices = mesh.polygons[face].vertices
    print(f"Face {face} corresponds to vertices: {vertices}")
    
# Switch back to Edit Mode
bpy.ops.object.mode_set(mode='EDIT')
