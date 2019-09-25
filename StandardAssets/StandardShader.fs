uniform sampler2D main_texture; // texture unit 0

#ifdef NORMAL_MAP
uniform sampler2D texture_normal_map; // texture unit 1
#endif

uniform float brightness = 1.0;
uniform float contrast = 1.0;

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

out vec4 outColour;

void main() { 
	vec3 trueColour = pass_colour;

	#if MAX_FRAGMENT_LIGHTS == 0 || !defined(HAS_NORMALS)
		// No lighting calulations to be done, use light value from vertex shader
		trueColour *= pass_light;
	#else


		#ifdef NORMAL_MAP
			vec3 tangentSpaceV = texture(texture_normal_map, pass_texture_coordinates).xyz * 2.0 - 1.0;
			vec3 n = pass_tangentToWorld * tangentSpaceV;
			n = normalize(n);

			trueColour *= apply_lighting(pass_light, pass_position, n);
			
		#else
			trueColour *= apply_lighting(pass_light, pass_position, pass_normal);
		#endif

	#endif

	#ifdef HAS_TEXTURE_COORDINATES
		trueColour *= texture(main_texture, pass_texture_coordinates).rgb;
	#endif

	// Colour correction

	const vec3 luminanceMultipliers = vec3(0.2126, 0.7152, 0.0722);
	float lum = dot(trueColour, luminanceMultipliers);

	float scale = brightness * pow(lum, contrast-1.0);

	outColour = vec4(trueColour.rgb*scale,1.0);
}
