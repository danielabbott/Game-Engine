#version 330

uniform vec2 window_dimensions;

in vec2 in_coords;

out vec2 pass_texture_coordinates;

void main() {
	pass_texture_coordinates = (in_coords * 0.5 + 0.5) * window_dimensions;
	gl_Position = vec4(in_coords, 0, 1);
}
