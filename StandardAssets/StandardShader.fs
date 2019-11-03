precision mediump float;

uniform sampler2D main_texture; // texture unit 0

#ifdef NORMAL_MAP
uniform sampler2D texture_normal_map; // texture unit 1
#endif

#if defined(HAS_NORMALS) && MAX_FRAGMENT_LIGHTS > 0
	#ifndef NORMAL_MAP
		in vec3 pass_normal;
	#endif

	in vec3 pass_position;

	#ifdef NORMAL_MAP
		in mat3 pass_tangentToWorld;
	#endif
#endif


#ifdef HAS_TEXTURE_COORDINATES
	in vec2 pass_texture_coordinates;
#endif

in vec3 pass_colour;
in vec3 pass_light;

out vec3 outColour;

void main() { 
	vec3 colour = pass_colour;

	#if MAX_FRAGMENT_LIGHTS == 0 || !defined(HAS_NORMALS)
		// No lighting calulations to be done, use light value from vertex shader
		colour *= pass_light;
	#else


		#ifdef NORMAL_MAP
			vec3 tangentSpaceV = texture(texture_normal_map, pass_texture_coordinates).xyz * 2.0 - 1.0;
			vec3 n = pass_tangentToWorld * tangentSpaceV;
			n = normalize(n);

			colour *= apply_lighting(pass_light, pass_position, n);
			
		#else
			colour *= apply_lighting(pass_light, pass_position, pass_normal);
		#endif

	#endif

	#ifdef HAS_TEXTURE_COORDINATES
		colour *= texture(main_texture, pass_texture_coordinates).rgb;
	#endif

	outColour = colour;
}
