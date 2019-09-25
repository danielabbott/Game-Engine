# THIS SCRIPT OUTPUTS .MODEL FILES
# THESE FILES ARE A CUSTOM BINARY (NOT ASCII) FILE FORMAT USED BY THE GAME ENGINE
# THE SCRIPT IS DESIGNED FOR EXPORTING SINGLE CHARACTER MODELS, SINGLE OBJECT MODELS, OR STATIC SCENES.

# BEFORE EXPORTING:
#	APPLY TRANSFORMS FOR ALL OBJECTS (TODO transform could be applied in the script)
# 	APPLY ALL MODIFIERS THAT EFFECT THE MESH (ARMATURE DEFORM CAN STAY)
# 	SWITCH TO OBJECT MODE

# N.B.  THE MATERIAL COLOURS COME FROM THE 'VIEWPORT DISPLAY -> COLOR' SETTING

# CONFIGURATION

EXPORT_FILE = '' # if set to '' will use the blend file name but change '.blend' to '.model'
EXPORT_BONES = True
EXPORT_TEX_COORDS = True
#EXPORT_INTERLEAVED = True# TODO
EXPORT_FLAT_SHADING = False
EXPORT_TANGENTS = True # Needed for normal maps


# IMPORTS

import bpy
import os
import struct
import traceback
import sys
import mathutils
from mathutils import Vector
import math

file = None

def main():
	global EXPORT_FILE
	global EXPORT_BONES
	global EXPORT_TEX_COORDS
	global EXPORT_FLAT_SHADING
	global EXPORT_TANGENTS
	global file

	if EXPORT_TANGENTS and not EXPORT_TEX_COORDS:
		print('EXPORT_TANGENTS requires EXPORT_TEX_COORDS')
		return

	materials = [] # unique materials (these are written to the .model file)
	materialsMapping = [None] * len(bpy.data.materials) # converts index into bpy.data.materials to index into materials

	for i, m in enumerate(bpy.data.materials, start=0):
		isNewMat = True
		for j, m2 in enumerate(materials, start=0):
			if m2.diffuse_color == m.diffuse_color:
				isNewMat = False
				materialsMapping[i] = j
				break

		if isNewMat:
			materialsMapping[i] = len(materials)
			materials.append(m)
		

	if len(materials) > 8:
		print('Too many materials. Maximum is 8.')

	# bpy.ops.object.mode_set(mode='OBJECT', toggle=False)

	# FUNCTIONS
	
	def writeByte(file, i, signed=False):
		file.write(i.to_bytes(1, byteorder='little', signed=signed))
	
	def writeWord(file, i, signed=False):
		file.write(i.to_bytes(2, byteorder='little', signed=signed))
	
	def writeDWord(file, i, signed=False):
		file.write(i.to_bytes(4, byteorder='little', signed=signed))
		
	def writeFloat(file, f):
		file.write(bytearray(struct.pack("f", f)))
		
	# Writes string length and string data then aligns to 4 bytes
	def writeString(file, s, encoding):
		encodedName = s.encode(encoding)
		writeByte(file, len(encodedName))
		file.write(encodedName)
				
		padding = 4 - ((len(encodedName)+1) % 4)
		if padding != 4:
			zero = 0
			file.write(zero.to_bytes(padding, byteorder='little', signed=False))
			
	def writeUTF8(file, s):
		writeString(file, s, 'utf8')
	
	def writeASCII(file, s):
		writeString(file, s, 'ascii')
		
	def switchCoordSystem(coords):
		return [coords[0], coords[2], -coords[1]]
		
		
	# EXECUTION BEGINS

	if EXPORT_FILE == '':
		EXPORT_FILE = os.path.splitext(bpy.data.filepath)[0] + '.model'
		
	print('Exporting ' + EXPORT_FILE)

	# Get vertices and indices

	class Vertex:
		pass
		
	vertices = []
	# size of vertices ^ before splitting vertices
	originalVertexArraySize = 0
	# index into vertices for each object in the blender scene
	objVertexOffsets = []

	i = 0
	for obj in bpy.data.objects:
		if hasattr(obj.data, 'polygons'):
			if EXPORT_FLAT_SHADING:
				obj.data.calc_normals()
			if EXPORT_TANGENTS:
				obj.data.calc_tangents()
			
			objVertexOffsets.append(i)
			for vertex in obj.data.vertices:

				v = Vertex()
				v.visited = False
				v.obj = obj
				v.co = vertex.co
				if not EXPORT_FLAT_SHADING:
					v.normal = vertex.normal
				else:
					v.normal = None

				# UV coordinates are not stored per-vertex in blender
				# They are added to our vertex objects later in the script
				v.uv = None

				# Tangent depends on uv coords ^ and is per-face. The value for each vertex is the average of it's faces tangents
				v.tangent = Vector((0.0,0.0,0.0),)
				v.tangentN = 0 # For calculating the average
				v.biTangentMul = 1.0

				vertices.append(v)
			originalVertexArraySize += len(obj.data.vertices)
			i += len(obj.data.vertices)

	indices = []
	
	# Used for exporting bone indices of new vertices
	# Vertices may be created where necessary where two textures meet
	newVerticies_listIndex = []
	newVertices_originalVertexIndex = []

	i = 0
	for obj in bpy.data.objects:
		if hasattr(obj.data, 'polygons'):
			for polygon in obj.data.polygons:
				if len(polygon.vertices) > 4:
					print('Only triangles and quadrilaterals are supported. Triangulate the mesh(es).')
					return
				elif len(polygon.vertices) < 3:
					continue

					
				if len(polygon.vertices) == 4:
					polygonIndices = [polygon.vertices[0], polygon.vertices[1], polygon.vertices[2], polygon.vertices[2], polygon.vertices[3], polygon.vertices[0]]
					polygonLoopIndices = (polygon.loop_indices[0], polygon.loop_indices[1], polygon.loop_indices[2], polygon.loop_indices[2], polygon.loop_indices[3], polygon.loop_indices[0])
				else:
					# Index into obj.data.vertices
					polygonIndices = [polygon.vertices[0], polygon.vertices[1], polygon.vertices[2]]

					# Index into uv layer
					polygonLoopIndices = polygon.loop_indices
			
				thisPolyTangent = obj.data.loops[polygonLoopIndices[0]].tangent
				biTangentMul = obj.data.loops[polygonLoopIndices[0]].bitangent_sign

				j = 0
				for vertex in polygonIndices:
					uv = obj.data.uv_layers.active.data[polygonLoopIndices[j]].uv if obj.data.uv_layers.active is not None else None
					v = vertices[objVertexOffsets[i] + vertex]

					if EXPORT_FLAT_SHADING and v.normal == None:
						v.normal = polygon.normal

					def newVertex():
						indices.append(len(vertices))
						newVerticies_listIndex.append(len(vertices))
						newVertices_originalVertexIndex.append(objVertexOffsets[i] + vertex)
						newVertex = Vertex()
						newVertex.co = v.co
						if EXPORT_FLAT_SHADING:
							newVertex.normal = polygon.normal
						else:
							newVertex.normal = v.normal
						newVertex.uv = uv
						newVertex.obj = obj
						newVertex.tangent = thisPolyTangent
						newVertex.tangentN = 1
						newVertex.biTangentMul = biTangentMul
						vertices.append(newVertex)	
						
					if EXPORT_FLAT_SHADING and v.normal != polygon.normal:
						newVertex()
					else:
						if (uv is None) or not EXPORT_TEX_COORDS:
							v.tangent = v.tangent + thisPolyTangent
							v.tangentN += 1
							v.biTangentMul = biTangentMul
							indices.append(objVertexOffsets[i] + vertex)
						elif v.uv is None:
							v.uv = uv
							v.tangent = v.tangent + thisPolyTangent
							v.tangentN += 1
							v.biTangentMul = biTangentMul
							indices.append(objVertexOffsets[i] + vertex)
						elif v.uv[0] == uv.x and v.uv[1] == uv.y:
							v.tangent = v.tangent + thisPolyTangent
							v.tangentN += 1
							v.biTangentMul = biTangentMul
							indices.append(objVertexOffsets[i] + vertex)
						else:						
							newVertex()	
					v.visited = True				
						
					j += 1
						
			i += 1

	# Materials

	indexLists = [[] for i in range(len(materials))]

	currentIndex = 0 # index into indices list
	for obj in bpy.data.objects:
		if hasattr(obj.data, 'polygons'):
			hasMaterials = len(obj.data.materials) > 0
			for polygon in obj.data.polygons:
				if len(polygon.vertices) < 3:
					continue

				# TODO: Cache values
				if len(obj.data.materials) > 0:
					matIndex = materialsMapping[bpy.data.materials.find(obj.data.materials[polygon.material_index].name)]
				else:
					matIndex = 0

				if matIndex < 0:
					print('polygon.material_index invalid')
					continue

				if len(polygon.vertices) == 4:
					polygonIndices = [polygon.vertices[0], polygon.vertices[1], polygon.vertices[2], polygon.vertices[2], polygon.vertices[3], polygon.vertices[0]]
				else:
					polygonIndices = [polygon.vertices[0], polygon.vertices[1], polygon.vertices[2]]

				for i in range(len(polygonIndices)):
					indexLists[matIndex].append(indices[currentIndex+i])


				currentIndex += len(polygonIndices)

	totalIndices = 0
	for i in indexLists:
		totalIndices += len(i)
	
	if EXPORT_TANGENTS:
		for v in vertices:
			if v.tangentN != 0:
				v.tangent = v.tangent / float(v.tangentN)



	# Write file
	
	file = open(EXPORT_FILE, 'wb')

	# Write magic

	writeDWord(file, 0xaaeecdbb)

	# Write number of indices

	writeDWord(file, totalIndices)


	# Specify vertex components

	attribs = 1 | (1 << 3)

	if EXPORT_TEX_COORDS:
		attribs = attribs | (1 << 2)
	
	if EXPORT_BONES:
		attribs = attribs | (1 << 4)
		attribs = attribs | (1 << 5)

	if EXPORT_TANGENTS:
		attribs = attribs | (1 << 6)
				
	writeDWord(file, attribs)
		
	writeDWord(file, 0) # Not interleaved
		
	writeDWord(file, len(vertices))



	# Write Vertices
	
	# All vertex attributes are stored in seperate arrays

	# TODO: Store vertex positions as 32-bit unsigned normalised integers and shrink the model down (doesn't need to stay in proportion)
	# and translate it to fit in the 1x1x1 box. then store the models scale and offset in the file to be used in the 
	# transformation matrix.
	# ^ actually that might mess up bone deformation
			
	for vertex in vertices:
		# loc = switchCoordSystem(vertex.co)
		loc = switchCoordSystem(vertex.obj.matrix_world @ vertex.co)
		for i in range(3):
			writeFloat(file, loc[i])
		
	if EXPORT_TEX_COORDS:
		for vertex in vertices:		
			if vertex.uv is None:
				writeDWord(file, 0)
			else:
				x = int(max(min(vertex.uv[0], 1.0), 0.0) * 65535.0)
				writeWord(file, x, False)
				
				y = int(max(min(1.0 - vertex.uv[1], 1.0), 0.0) * 65535.0)
				writeWord(file, y, False)
				
	
	for vertex in vertices:
		# normals = switchCoordSystem(vertex.normal)
		normals = switchCoordSystem(vertex.obj.matrix_world @ vertex.normal)
		
		nx = int(normals[2] * 511.0)
		ny = int(normals[1] * 511.0)
		nz = int(normals[0] * 511.0)
		
		x = (nz & 1023) | ((ny & 1023) << 10) | ((nx & 1023) << 20)
		writeDWord(file, x)	

	if EXPORT_BONES:
		# Bone Weights

		allbones = []
		allbones_objects = []
		
		for o in bpy.data.objects:
			if hasattr(o.data, 'bones') and hasattr(o, 'pose') and o.pose != None:
				for b in o.data.bones:
					allbones.append(b)
					allbones_objects.append(o)
		
		
		boneIndices = [[0,0,0,0] for i in range(len(vertices))]
		boneWeights = [[0.0,0.0,0.0,0.0] for i in range(len(boneIndices))]
		
		def findIndexOfBone(allbones, name):
			k = 0
			for bone in allbones:
				if bone.name == name:
					return k
				k += 1
			return -1
				
				
		objIndex = 0
		for obj in bpy.data.objects:
			if hasattr(obj.data, 'polygons'):
				for j in range(len(obj.data.vertices)):
					k = 0
					for vgroup in obj.vertex_groups:
						try:
							weight = vgroup.weight(j)
							if weight > 0.0:
								# TODO pick 4 most significant weights (and order from biggest to smallest influence)
								boneIndices[objVertexOffsets[objIndex] + j][k] = findIndexOfBone(allbones, vgroup.name)
								boneWeights[objVertexOffsets[objIndex] + j][k] = weight
								k += 1
								if k >= 4:
									break
						except:
							pass
				objIndex += 1
				
		for i in range(len(newVerticies_listIndex)):
			boneIndices[newVerticies_listIndex[i]] = boneIndices[newVertices_originalVertexIndex[i]]
			boneWeights[newVerticies_listIndex[i]] = boneWeights[newVertices_originalVertexIndex[i]]
	
		for i in boneIndices:
			for j in i:
				writeByte(file, j)
			
		for i in boneWeights:
			for j in i:
				writeByte(file, int(j * 255.0))
	

	if EXPORT_TANGENTS:		
		for vertex in vertices:
			# tangent = switchCoordSystem(vertex.tangent)
			tangent = switchCoordSystem(vertex.obj.matrix_world @ vertex.tangent)
			
			tx = int(tangent[2] * 511.0)
			ty = int(tangent[1] * 511.0)
			tz = int(tangent[0] * 511.0)
			
			if vertex.biTangentMul == -1.0:
				w = 1 << 30
			else:
				w = 3 << 30
			
			
			x = (tz & 1023) | ((ty & 1023) << 10) | ((tx & 1023) << 20) | w
			writeDWord(file, x)
		

			
	# Write Indices
	
	if len(vertices) <= 65536:
		totalLen = 0
		for j in indexLists:
			for i in j:
				writeWord(file, i)
			totalLen += len(j)
		if totalLen % 2 != 0:
			writeWord(file, 0)
	else:
		for j in indexLists:
			for i in j:
				writeDWord(file, i)


	# Write materials
	
	writeDWord(file, len(materials))

	indexStart = 0
	for i, mat in enumerate(materials, start=0):
		writeDWord(file, indexStart)
		writeDWord(file, len(indexLists[i]))
		indexStart += len(indexLists[i])
		writeFloat(file, mat.diffuse_color[0])
		writeFloat(file, mat.diffuse_color[1])
		writeFloat(file, mat.diffuse_color[2])
		
		writeUTF8(file, mat.name)
	
	if EXPORT_BONES and len(allbones) > 0:
		
		writeDWord(file, len(allbones))
		i = 0
		for b in allbones:
			# Position around which the vertices rotate
			head = allbones_objects[i].matrix_world @ b.head_local
			switchCoordSystem(head)
			
			# End of bone
			tail = allbones_objects[i].matrix_world @ b.tail_local
			switchCoordSystem(tail)
			
			for i in range(3):
				writeFloat(file, head[i])
			for i in range(3):
				writeFloat(file, tail[i])
			
			# Bone parent index
			if b.parent is None:
				writeDWord(file, -1, True)
			else:
				index = allbones.index(b.parent)
				writeDWord(file, index, True)
			
				
			writeUTF8(file, b.name)
			
			i += 1

		
	else:
		writeDWord(file, 0)

	print('Mesh export complete')

main()

if file != None:
	file.close()
