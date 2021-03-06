#version 330

uniform sampler2D textureSrc;

const vec2 in_coords[3] = vec2[]
(
    vec2(-6.0,  -1.0),
    vec2( 1.0,  -1.0),
    vec2( 1.0, 6.0)
);

out vec2 pass_texture_coordinates;
flat out vec2 inverseSize;

void main() {
    inverseSize = 1.0 / textureSize(textureSrc, 0);
	pass_texture_coordinates = (in_coords[gl_VertexID] * 0.5 + 0.5);
	gl_Position = vec4(in_coords[gl_VertexID], 0, 1);
}
