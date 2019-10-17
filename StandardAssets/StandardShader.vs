#ifndef SHADOW_MAP
uniform vec3 object_colour;
uniform vec3 per_obj_light;
#endif

in vec3 in_coords;

#ifdef HAS_VERTEX_COLOURS
	in vec4 in_vertex_colour;
#endif

#ifdef HAS_TEXTURE_COORDINATES
	in vec2 in_texture_coordinates;
#endif

#ifdef HAS_NORMALS
	in vec4 in_normal;
	uniform mat3 normalMatrix;
#endif

#ifdef HAS_VERTEX_WEIGHTS
	in uvec4 in_bone_indices;
	in vec4 in_vertex_weights;
#endif


#ifdef NORMAL_MAP
	in vec4 in_tangent;
#endif

#ifndef SHADOW_MAP

	#ifdef ENABLE_SHADOWS
		out SHADOW_COORDS_PASS_VAR_TYPE shadowDepthMapCoordinates;
	#endif

	#ifdef HAS_TEXTURE_COORDINATES
		out vec2 pass_texture_coordinates;
	#endif

	#if defined(HAS_NORMALS) && MAX_FRAGMENT_LIGHTS > 0
		#ifndef NORMAL_MAP
			out vec3 pass_normal;
		#endif

		out vec3 pass_position;

		#ifdef NORMAL_MAP
			out mat3 pass_tangentToWorld;
		#endif
	#endif

	out vec3 pass_colour;
	out vec3 pass_light;

#endif



// Skeletal animation

#if defined(HAS_VERTEX_WEIGHTS) && defined(HAS_VERTEX_COORDINATES)
uniform mat4 boneMatrices[128];

#ifdef HAS_NORMALS
void apply_animation(inout vec4 position, inout vec3 normal) {		
#else
void apply_animation(inout vec4 position) {		
#endif
	mat4 boneMat1 = boneMatrices[min(127u, in_bone_indices[0])];	
	mat4 boneMat2 = boneMatrices[min(127u, in_bone_indices[1])];	
	mat4 boneMat3 = boneMatrices[min(127u, in_bone_indices[2])];	
	mat4 boneMat4 = boneMatrices[min(127u, in_bone_indices[3])];

	vec3 position1 = (boneMat1 * position).xyz;
	vec3 position2 = (boneMat2 * position).xyz;
	vec3 position3 = (boneMat3 * position).xyz;
	vec3 position4 = (boneMat4 * position).xyz;

	position = vec4(
		position1 * in_vertex_weights[0] +
		position2 * in_vertex_weights[1] +
		position3 * in_vertex_weights[2] +
		position4 * in_vertex_weights[3]
		, 1.0);

#ifdef HAS_NORMALS
	vec3 normal1 = normalize(mat3(boneMat1) * normal);
	vec3 normal2 = normalize(mat3(boneMat2) * normal);
	vec3 normal3 = normalize(mat3(boneMat3) * normal);
	vec3 normal4 = normalize(mat3(boneMat4) * normal);

	normal = 
		normal1 * in_vertex_weights[0] +
		normal2 * in_vertex_weights[1] +
		normal3 * in_vertex_weights[2] +
		normal4 * in_vertex_weights[3];
#endif
}
#endif

// Main

#ifndef HAS_VERTEX_COORDINATES
const vec2 square_coordinates[6] = vec2[6](
	vec2(0, 0),
	vec2(1, 0),
	vec2(1, 1),
	vec2(1, 1),
	vec2(0, 1),
	vec2(0, 0)
); 
#endif

void main() {
#ifdef HAS_NORMALS
	vec3 normal = in_normal.xyz;
#endif
	
#ifdef HAS_VERTEX_COORDINATES
	vec4 coordinates = vec4(in_coords, 1.0);

	#ifdef HAS_VERTEX_WEIGHTS
		#ifdef HAS_NORMALS
			apply_animation(coordinates, normal);
		#else
			apply_animation(coordinates);
		#endif
	#endif

#else
	vec4 coordinates = vec4(square_coordinates[gl_VertexID % 6], 0, 1);
#endif
	gl_Position = mvp_matrix * coordinates;

#ifndef SHADOW_MAP

	#ifdef HAS_TEXTURE_COORDINATES
		pass_texture_coordinates = in_texture_coordinates;
	#endif
		
	#ifdef HAS_VERTEX_COLOURS
		pass_colour = in_vertex_colour.rgb * object_colour;
	#else
		pass_colour = object_colour;
	#endif

	#ifdef HAS_NORMALS
		#ifdef ENABLE_NON_UNIFORM_SCALE
			vec3 normalWorldSpace = normalize(normalMatrix * normal);

			#ifdef NORMAL_MAP
				vec3 tangentWorldSpace = normalize(normalMatrix * in_tangent.xyz);
			#endif

		#else
			vec3 normalWorldSpace = normalize((model_matrix * vec4(normal, 0.0)).xyz);

			#ifdef NORMAL_MAP
				vec3 tangentWorldSpace = normalize((model_matrix * vec4(in_tangent.xyz, 0.0)).xyz);
			#endif
		#endif

		vec3 pos = (model_matrix * coordinates).xyz;

		#if MAX_FRAGMENT_LIGHTS > 0
			#ifndef NORMAL_MAP
				pass_normal = normalWorldSpace;
			#endif
			
			pass_position = pos;

			#ifdef ENABLE_SHADOWS
				#if MAX_FRAGMENT_LIGHTS == 1
					shadowDepthMapCoordinates = lightMatrices[0] * vec4(pos, 1.0);
				#else
					SHADOW_COORDS_PASS_VAR_TYPE depthMapCoords = SHADOW_COORDS_PASS_VAR_TYPE(1.0);
					depthMapCoords[0] = lightMatrices[0] * vec4(pos, 1.0);
					#if MAX_FRAGMENT_LIGHTS >= 2
						depthMapCoords[1] = lightMatrices[1] * vec4(pos, 1.0);
					#endif
					#if MAX_FRAGMENT_LIGHTS >= 3
						depthMapCoords[2] = lightMatrices[2] * vec4(pos, 1.0);
					#endif
					#if MAX_FRAGMENT_LIGHTS >= 4
						depthMapCoords[3] = lightMatrices[3] * vec4(pos, 1.0);
					#endif
					shadowDepthMapCoordinates = depthMapCoords;
				#endif
			#endif
		#endif
		
		#if MAX_VERTEX_LIGHTS > 0
			pass_light = apply_lighting(per_obj_light, pos, normalWorldSpace);
		#else
			pass_light = per_obj_light;
		#endif

		#if defined(NORMAL_MAP) && MAX_FRAGMENT_LIGHTS > 0
			pass_tangentToWorld = mat3(model_matrix) * mat3(
				vec3(tangentWorldSpace), 
				vec3(cross(normalWorldSpace, tangentWorldSpace)*in_tangent.w), 
				vec3(normal) 
			);
		#endif
	#else
		pass_light = per_obj_light;
	#endif

#endif // !SHADOW_MAP
}

