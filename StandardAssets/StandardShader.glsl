precision mediump float;

uniform mat4 mvp_matrix;
uniform mat4 model_matrix;

#if defined(ENABLE_SHADOWS) && MAX_FRAGMENT_LIGHTS == 0
	#undef ENABLE_SHADOWS
#endif

#if !defined(ENABLE_POINT_LIGHTS) && !defined(ENABLE_DIRECTIONAL_LIGHTS) && !defined(ENABLE_SPOT_LIGHTS)
	#undef MAX_FRAGMENT_LIGHTS
	#define MAX_FRAGMENT_LIGHTS 0
	#undef MAX_VERTEX_LIGHTS
	#define MAX_VERTEX_LIGHTS 0
	#ifdef ENABLE_SHADOWS
		#undef ENABLE_SHADOWS
	#endif
#elif (defined(ENABLE_POINT_LIGHTS) && !defined(ENABLE_DIRECTIONAL_LIGHTS) && !defined(ENABLE_SPOT_LIGHTS)) || (!defined(ENABLE_POINT_LIGHTS) && defined(ENABLE_DIRECTIONAL_LIGHTS) && !defined(ENABLE_SPOT_LIGHTS)) || (!defined(ENABLE_POINT_LIGHTS) && !defined(ENABLE_DIRECTIONAL_LIGHTS) && defined(ENABLE_SPOT_LIGHTS))
	#define ONLY_ONE_LIGHT_TYPE
#endif

#ifdef VERTEX_SHADER
	#define MAX_LIGHTS MAX_VERTEX_LIGHTS
	#if MAX_LIGHTS > 0
		uniform int vertex_lights[MAX_LIGHTS];
		#define LIGHTS vertex_lights
	#endif
#else
	#define MAX_LIGHTS MAX_FRAGMENT_LIGHTS
	#if MAX_LIGHTS > 0
		uniform int fragment_lights[MAX_LIGHTS];
		#define LIGHTS fragment_lights
	#endif
#endif

#if defined(ENABLE_SHADOWS) && MAX_FRAGMENT_LIGHTS > 0
	uniform mat4 lightMatrices[4]; // light_ortho * light_view
#endif

#if MAX_FRAGMENT_LIGHTS > 0 && defined(ENABLE_SHADOWS)
	#if MAX_FRAGMENT_LIGHTS == 1
		#define SHADOW_COORDS_PASS_VAR_TYPE vec4
		#define GET_SHADOW_COORDS(i) shadowDepthMapCoordinates
	#else
		#define SHADOW_COORDS_PASS_VAR_TYPE mat4x##MAX_FRAGMENT_LIGHTS
		#define GET_SHADOW_COORDS(i) shadowDepthMapCoordinates[i]
	#endif
#endif

#if MAX_LIGHTS > 0

	#ifdef ENABLE_SPECULAR
		// 0 - 1. The closer the number is  to 0, the bigger the highlight.
		uniform float specularSize = 0.95;

		uniform float specularIntensity = 10.0;

		// 0 - 1. 1 = specular highlight colour matches light colour. 0 = White highlights
		uniform float specularColouration = 0.05;
	#endif

	#define LIGHT_TYPE_NONE 0.0
	#ifdef ENABLE_POINT_LIGHTS
		#define LIGHT_TYPE_POINT 1.0
		#define LIGHT_TYPE_POINT_WITH_SHADOWS 2.0
	#endif
	#ifdef ENABLE_DIRECTIONAL_LIGHTS
		#define LIGHT_TYPE_DIRECTIONAL 3.0
		#define LIGHT_TYPE_DIRECTIONAL_WITH_SHADOWS 4.0
	#endif
	#ifdef ENABLE_SPOT_LIGHTS
		#define LIGHT_TYPE_SPOTLIGHT 5.0
		#define LIGHT_TYPE_SPOTLIGHT_WITH_SHADOWS 6.0
	#endif


	struct Light {
		// w = type
		vec4 positionAndType;

		// w = cos(angle) (for spotlight)
		vec4 directionAndAngle;

		// w = attenuation
		vec4 intensity;
	};

	// Data is set at the start of each frame
	layout(std140) uniform UniformData {
		vec4 eyePosition;
		Light all_lights[256];
	};



	#if defined(ENABLE_SHADOWS) && defined(FRAGMENT_SHADER)

		uniform sampler2D shadowTexture0; // texture unit 2
		uniform sampler2D shadowTexture1; // texture unit 3
		uniform sampler2D shadowTexture2; // texture unit 4
		uniform sampler2D shadowTexture3; // texture unit 5

		#ifdef ENABLE_POINT_LIGHTS
			uniform samplerCube shadowCubeTexture0; // texture unit 6
			uniform samplerCube shadowCubeTexture1; // texture unit 7
			uniform samplerCube shadowCubeTexture2; // texture unit 8
			uniform samplerCube shadowCubeTexture3; // texture unit 9

			uniform float nearPlanes[4];
			uniform float farPlanes[4];
		#endif

		in SHADOW_COORDS_PASS_VAR_TYPE shadowDepthMapCoordinates;
	#endif
	// prevLight: Result from previous lighting stage
	// positionWorldSpace: position of vertex/fragment in world space
	// normal: normal of fragment in model space

	#ifdef ENABLE_SPECULAR
		void specular(vec3 normal, vec3 positionWorldSpace, vec3 lightAngle, vec3 lightIntensity, inout vec3 colour) {
			float specular = dot(normalize(positionWorldSpace-eyePosition.xyz), reflect(lightAngle, normal))-specularSize;
			colour += mix(vec3(1.0), normalize(lightIntensity), specularColouration) * specularIntensity * max(0.0, specular);
		}
	#endif

	#if defined(ENABLE_SHADOWS) && (defined(ENABLE_DIRECTIONAL_LIGHTS) || defined(ENABLE_SPOT_LIGHTS)) && defined(FRAGMENT_SHADER)
		float doShadow(int i, bool perspective) {
			vec3 lightMapCoords;
			vec3 lightMapCoords01;
			
			vec4 lightMapCoordsxyzw = GET_SHADOW_COORDS(i);
			lightMapCoordsxyzw.xyz /= lightMapCoordsxyzw.w;
			lightMapCoords = lightMapCoordsxyzw.xyz;
			lightMapCoords01 = lightMapCoords*0.5+0.5;
			

			if(any( greaterThan(abs(lightMapCoords.xy), vec2(1.0)) )) {
				return 1.0;
			}

			ivec2 shadowMapSize;
			vec2 a = 1.0 / shadowMapSize;
			float shadowValueCentre;

			#if MAX_FRAGMENT_LIGHTS == 1
				shadowMapSize = textureSize(shadowTexture0, 0);
				shadowValueCentre = texture(shadowTexture0, lightMapCoords01.xy).r;
			#else
				#define TEX(II) \
					if(i == II) { \
						shadowMapSize = textureSize(shadowTexture##II, 0); \
						shadowValueCentre = texture(shadowTexture##II, lightMapCoords01.xy).r; \
					}

				TEX(0)
				#if MAX_FRAGMENT_LIGHTS >= 2
					TEX(1)
				#endif
				#if MAX_FRAGMENT_LIGHTS >= 3
					TEX(2)
				#endif
				#if MAX_FRAGMENT_LIGHTS >= 4
					TEX(3)
				#endif
				#undef TEX
			#endif

			const float shadowGap = 0.00001;

			if(shadowValueCentre == 0) {
				return 1.0;
			}

			if(shadowValueCentre-lightMapCoords.z > shadowGap) {
				// In shadow
				
				vec4 shadowValuesSides;
				vec4 shadowValuesCorners;

				#if MAX_FRAGMENT_LIGHTS == 1
					shadowValuesSides = vec4(textureOffset(shadowTexture0, lightMapCoords01.xy, ivec2(2, 0)).r,
					textureOffset(shadowTexture0, lightMapCoords01.xy, ivec2(-2, 0)).r,
					textureOffset(shadowTexture0, lightMapCoords01.xy, ivec2(0, 2)).r,
					textureOffset(shadowTexture0, lightMapCoords01.xy, ivec2(0, -2)).r);
					
					shadowValuesCorners = vec4(textureOffset(shadowTexture0, lightMapCoords01.xy, ivec2(1, 1)).r,
					textureOffset(shadowTexture0, lightMapCoords01.xy, ivec2(-1, -1)).r,
					textureOffset(shadowTexture0, lightMapCoords01.xy, ivec2(+1, -1)).r,
					textureOffset(shadowTexture0, lightMapCoords01.xy, ivec2(-1, 1)).r);
				#else
					#define TEX(II) \
						if(i == II) { \
							shadowValuesSides = vec4(textureOffset(shadowTexture##II, lightMapCoords01.xy, ivec2(2, 0)).r, \
							textureOffset(shadowTexture##II, lightMapCoords01.xy, ivec2(-2, 0)).r, \
							textureOffset(shadowTexture##II, lightMapCoords01.xy, ivec2(0, 2)).r, \
							textureOffset(shadowTexture##II, lightMapCoords01.xy, ivec2(0, -2)).r); \
							\
							shadowValuesCorners = vec4(textureOffset(shadowTexture##II, lightMapCoords01.xy, ivec2(1, 1)).r, \
							textureOffset(shadowTexture##II, lightMapCoords01.xy, ivec2(-1, -1)).r, \
							textureOffset(shadowTexture##II, lightMapCoords01.xy, ivec2(+1, -1)).r,\
							textureOffset(shadowTexture##II, lightMapCoords01.xy, ivec2(-1, 1)).r); \
						}

					TEX(0)
					TEX(1)
					TEX(2)
					TEX(3)
					#undef TEX
				#endif


				// for(int i = 0; i < 4; i++) {
				// 	if(shadowValuesSides[i]-lightMapCoords.z < shadowGap) {
				// 		// If not in shadow
				// 		light += 0.15;
				// 	}
				// 	if(shadowValuesCorners[i]-lightMapCoords.z < shadowGap) {
				// 		light += 0.07;
				// 	}
				// }

				// These 3 lines are equivilent to the pseudocode above
				vec4 values1 = max(vec4(0.0), -sign(shadowValuesSides - vec4(lightMapCoords.z+shadowGap))) * vec4(0.15);
				vec4 values2 = max(vec4(0.0), -sign(shadowValuesCorners - vec4(lightMapCoords.z+shadowGap))) * vec4(0.07);

				// 0 = full shadow, 1.0 = not shadow
				float light = dot(values1, vec4(1.0)) + dot(values2, vec4(1.0));

				light = 1.0 - ((1.0-light)*(1.0-light));

				return 0.2 + smoothstep(0.0, 1.0, clamp(light, 0.0, 1.0)) * 0.8;
			}
			else {
				// Not in shadow
				return 1.0;
			}
		}
	#endif // defined(ENABLE_SHADOWS) && (defined(ENABLE_DIRECTIONAL_LIGHTS) || defined(ENABLE_SPOT_LIGHTS))

	vec3 apply_lighting(vec3 prevLight, vec3 positionWorldSpace, vec3 normal) {

		// Start with result from previous lighting stage (either per-object lighting or per-vertex lighting)
		vec3 c = prevLight;

	#if MAX_LIGHTS != 1
		for (int i = 0; i < MAX_LIGHTS; i++) {
			if(LIGHTS[i] < 0) {
				break;
			}
	#else
		#define i 0
		#ifndef ONLY_ONE_LIGHT_TYPE
			// Dummy if statement so all ifs below can start with else
			if(false) {}
		#endif
	#endif

			#define light all_lights[LIGHTS[i]]

	#ifdef ENABLE_POINT_LIGHTS
			#ifndef ONLY_ONE_LIGHT_TYPE
				else if(light.positionAndType.w == LIGHT_TYPE_POINT || light.positionAndType.w == LIGHT_TYPE_POINT_WITH_SHADOWS) {
			#endif
				vec3 objectToLight = light.positionAndType.xyz - positionWorldSpace;
				float dist = length(objectToLight);

				float shadowValue = 1.0;

				#if defined(ENABLE_SHADOWS) && defined(FRAGMENT_SHADER)
					if(light.positionAndType.w == LIGHT_TYPE_POINT_WITH_SHADOWS) {
						float shadowSample;
						float actualDepth;
						vec3 v = -objectToLight;
						
						#define TEX(II) \
							if(i == II) { \
								shadowSample = texture(shadowCubeTexture##II, v).r; \
							}

						TEX(0)
						TEX(1)
						TEX(2)
						TEX(3)
						#undef TEX

						actualDepth = (dist - nearPlanes[i]) / farPlanes[i];

						if(shadowSample > actualDepth) {
							shadowValue = 0.0;
						}
					}
				#endif

				float lightIntensity = clamp(dot(normalize(objectToLight), normal), 0, 1);

				float l = dist * light.intensity.w;
				float lenSqrd = l*l;
					
				lenSqrd = max(lenSqrd, 0.0001);
				
				lightIntensity /= lenSqrd;

				c += lightIntensity * light.intensity.rgb * shadowValue;
				#ifdef ENABLE_SPECULAR
				if(shadowValue == 1.0) {
					specular(normal, positionWorldSpace, normalize(objectToLight), light.intensity.xyz, c);
				}
				#endif
			#ifndef ONLY_ONE_LIGHT_TYPE
			}
			#endif
	#endif


	#ifdef ENABLE_DIRECTIONAL_LIGHTS


		#ifndef ONLY_ONE_LIGHT_TYPE
			else if(light.positionAndType.w == LIGHT_TYPE_DIRECTIONAL || light.positionAndType.w == LIGHT_TYPE_DIRECTIONAL_WITH_SHADOWS) {
		#endif

				float lightIntensity = max(dot(normal, light.directionAndAngle.xyz), 0.0);

				
				#if defined(ENABLE_SHADOWS) && defined(FRAGMENT_SHADER)
					float shadowEffect = 1.0;
					if(lightIntensity > 0.0) {
						shadowEffect = doShadow(i, false);
					}
					c += lightIntensity * light.intensity.xyz * shadowEffect;
				#else
					c += lightIntensity * light.intensity.xyz;
				#endif

				#ifdef ENABLE_SPECULAR
					specular(normal, positionWorldSpace, light.directionAndAngle.xyz, light.intensity.xyz, c);
				#endif			
		#ifndef ONLY_ONE_LIGHT_TYPE
			}
		#endif
	#endif // ENABLE_DIRECTIONAL_LIGHTS


	#ifdef ENABLE_SPOT_LIGHTS
	
		#ifndef ONLY_ONE_LIGHT_TYPE
		else if(light.positionAndType.w == LIGHT_TYPE_SPOTLIGHT || light.positionAndType.w == LIGHT_TYPE_SPOTLIGHT_WITH_SHADOWS) {
		#endif
		
			vec3 lightToObject = positionWorldSpace - light.positionAndType.xyz;
			vec3 lightToObjectN = normalize(lightToObject);

			// cosine of angle
			float angle = dot(lightToObjectN, -light.directionAndAngle.xyz);

			if(angle > 0 && angle > light.directionAndAngle.w) {			
				float lightIntensity = clamp(dot(-lightToObjectN, normal), 0, 1);

				#if defined(ENABLE_SHADOWS) && defined(FRAGMENT_SHADER)
					float shadowEffect = 1.0;
					if(light.positionAndType.w == LIGHT_TYPE_SPOTLIGHT_WITH_SHADOWS && lightIntensity > 0.0) {
						shadowEffect = doShadow(i, true);
					}
				#else
					const float shadowEffect = 1.0;
				#endif

				float l = length(lightToObject) * light.intensity.w;
				float lenSqrd = l*l;
					
				lenSqrd = max(lenSqrd, 0.0001);

				lightIntensity /= lenSqrd;
				
				float coneBrightness = (angle - light.directionAndAngle.w) / (1.0 - light.directionAndAngle.w);
				
				c += lightIntensity * light.intensity.xyz * coneBrightness * shadowEffect;

				#ifdef ENABLE_SPECULAR
					if(shadowEffect == 1.0) {
						specular(normal, positionWorldSpace, normalize(-lightToObject), light.intensity.xyz, c);
					}
				#endif
			}
		#ifndef ONLY_ONE_LIGHT_TYPE
		}
		#endif
	#endif // ENABLE_SPOT_LIGHTS

	#if MAX_LIGHTS != 1
			#ifndef ONLY_ONE_LIGHT_TYPE
			else {
				break;
			}
			#endif			
		}
	#endif

		return c;
	}

#endif // MAX_LIGHTS > 0

