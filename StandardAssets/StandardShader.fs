precision mediump float;

uniform sampler2D main_texture; // texture unit 0

#ifdef NORMAL_MAP
uniform sampler2D texture_normal_map; // texture unit 1
#endif

// If HAS_NORMALS is false and lighting is enabled then flat shading is used regardless of this setting
uniform bool flatShading = true;

#if MAX_FRAGMENT_LIGHTS > 0
	#if !defined(NORMAL_MAP) && defined(HAS_NORMALS)
		in vec3 pass_normal;
	#endif

	in vec3 pass_position;

	#if defined(NORMAL_MAP) && defined(HAS_NORMALS)
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

	#if MAX_FRAGMENT_LIGHTS == 0
		// No lighting calulations to be done, use light value from vertex shader
		colour *= pass_light;
	#else

		#ifdef NORMAL_MAP
			vec3 tangentSpaceV = texture(texture_normal_map, pass_texture_coordinates).xyz * 2.0 - 1.0;
			vec3 n = pass_tangentToWorld * tangentSpaceV;
			n = normalize(n);

			colour *= apply_lighting(pass_light, pass_position, n);
			
		#else
			vec3 normal;

			#ifdef HAS_NORMALS
				if(flatShading) {
			#endif
				// Normal of the face
				// Uses the change in world space position between fragments to calculate the normal
				normal = normalize(cross(dFdx(pass_position), dFdy(pass_position)));
			#ifdef HAS_NORMALS
				}
				else {
					normal = pass_normal;
				}
			#endif
			
			colour *= apply_lighting(pass_light, pass_position, normal);
		#endif

	#endif

	#ifdef HAS_TEXTURE_COORDINATES
		colour *= texture(main_texture, pass_texture_coordinates).rgb;
	#endif


	// fog
	colour = mix(colour, fogColour.rgb, fogColour.a * pow((clamp(1.0 - gl_FragCoord.z, 0.8, 1.0) - 0.8) * 5.0, 3.0));


	outColour = colour;
}
