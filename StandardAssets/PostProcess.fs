#version 330

uniform sampler2D framebuffer;

in vec2 pass_texture_coordinates;

uniform float brightness = 1.0;
uniform float contrast = 1.0;

out vec3 out_colour;

void main() {
	ivec2 int_coords = ivec2(pass_texture_coordinates);

	vec3 colours[5];

	colours[0] = texelFetch(framebuffer, int_coords, 0).rgb;
	colours[1] = texelFetch(framebuffer, ivec2(pass_texture_coordinates.x-0.5, pass_texture_coordinates.y-0.5), 0).rgb;
	colours[2] = texelFetch(framebuffer, ivec2(pass_texture_coordinates.x-0.5, pass_texture_coordinates.y+0.5), 0).rgb;
	colours[3] = texelFetch(framebuffer, ivec2(pass_texture_coordinates.x+0.5, pass_texture_coordinates.y-0.5), 0).rgb;
	colours[4] = texelFetch(framebuffer, ivec2(pass_texture_coordinates.x+0.5, pass_texture_coordinates.y+0.5), 0).rgb;

	const vec3 luminanceMultipliers = vec3(0.2126, 0.7152, 0.0722);

	float lum0 = dot(colours[0], luminanceMultipliers);
	float lum1 = dot(colours[1], luminanceMultipliers);
	float lum2 = dot(colours[2], luminanceMultipliers);
	float lum3 = dot(colours[3], luminanceMultipliers);
	float lum4 = dot(colours[4], luminanceMultipliers);

	float max_lum = max(lum0, max(lum1, max(lum2, max(lum3,lum4))));
	float min_lum = min(lum0, min(lum1, min(lum2, min(lum3,lum4))));

	float lum_range = max_lum - min_lum;

	vec3 colour;
	float lum;

	if(lum_range > 0.19) {
		colour = (colours[0]+colours[1]+colours[2]+colours[3]+colours[4]) / 5.0;
		lum = dot(colour, luminanceMultipliers);

		// Uncomment this line to highlight edges in red
		// colour = vec3(1.0,0.0,0.0);
	}
	else {
		colour = colours[0];
		lum = lum0;
	}

	// Colour correction


	float scale = brightness * pow(lum, contrast-1.0);
	out_colour = pow(vec3(colour.rgb*scale), vec3(1.0/2.2));

}
