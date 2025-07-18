set compiler="%VULKAN_SDK%/Bin/glslc.exe"
%compiler% src/shader.vert -o intermediate/vert.spv
%compiler% src/shader.frag -o intermediate/frag.spv
%compiler% -fshader-stage=compute src/cmp_draw_rect.glsl -o intermediate/cmp_draw_rect.spv
%compiler% -fshader-stage=compute src/compute_sphere.glsl -o intermediate/compute_sphere.spv
%compiler% -fshader-stage=compute src/cpt_draw_quad_textured.glsl -o intermediate/cpt_draw_quad_textured.spv
%compiler% src/mesh.vert -o intermediate/mesh_vert.spv
%compiler% src/mesh.frag -o intermediate/mesh_frag.spv
%compiler% src/color_mesh.vert -o intermediate/color_mesh_vert.spv
%compiler% src/color_mesh.frag -o intermediate/color_mesh_frag.spv
%compiler% src/unlit_color_mesh.frag -o intermediate/unlit_color_mesh_frag.spv
%compiler% src/line.vert -o intermediate/line_vert.spv
%compiler% src/line.frag -o intermediate/line_frag.spv
%compiler% -fshader-stage=compute src/compute_draw_capsule.glsl -o intermediate/compute_draw_capsule.spv
%compiler% -fshader-stage=compute src/copy_depth_image.glsl -o intermediate/copy_depth_image.spv