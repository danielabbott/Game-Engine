#version 330

uniform vec2 window_dimensions;

out vec2 pass_texture_coordinates;

const vec2 in_coords[3] = vec2[]
(
    vec2(-6.0,  -1.0),
    vec2( 1.0,  -1.0),
    vec2( 1.0, 6.0)
);

void main() {
	pass_texture_coordinates = (in_coords[gl_VertexID] * 0.5 + 0.5) * window_dimensions;
	gl_Position = vec4(in_coords[gl_VertexID], 0, 1);
}
