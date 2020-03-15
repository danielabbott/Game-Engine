EXPORT_FILE = 'C:/Users/dabbo/GameEngine/DemoAssets/Farm.scene'
AMBIENT = (0.1, 0.1, 0.15)
CLEAR_COLOUR = (0.1, 0.1, 0.15)
USING_COMPRESSED_MODELS = True # if true, model file names are *.model.compressed
USE_FLAT_SHADING = True # Set all objects to use flat (per-face) shading

import bpy
import struct
import mathutils
from mathutils import Vector,Matrix
from math import sin,cos,radians

# coordinateConversion: Blender <-> OpenGL coordinate system
		
toOpenGLCoords = Matrix()

# y,z = z,-y

toOpenGLCoords[1][1] = 0.0
toOpenGLCoords[1][2] = 1.0
toOpenGLCoords[2][1] = -1.0
toOpenGLCoords[2][2] = 0.0

toBlenderCoords = toOpenGLCoords.inverted()

rotate_light = Matrix()

sinTheta = sin(radians(-90))
cosTheta = cos(radians(-90))

rotate_light[1][1] = cosTheta
rotate_light[1][2] = -sinTheta
rotate_light[2][2] = cosTheta
rotate_light[2][1] = sinTheta

def convertMatrix(m):
	global toOpenGLCoords
	global toBlenderCoords
	return toOpenGLCoords @ m @ toBlenderCoords

def switchCoordSystem(coords):
	return [coords[0], coords[2], -coords[1]]
	
def writeByte(file, i, signed=False):
	file.write(i.to_bytes(1, byteorder='little', signed=signed))

def writeDWord(file, i, signed=False):
	file.write(i.to_bytes(4, byteorder='little', signed=signed))
		
def writeFloat(file, f):
	file.write(bytearray(struct.pack("f", f)))		

def writeMatrix(file, m):
	for i in range(4):
		for j in range(4):
			writeFloat(file, m[j][i])

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

def stringToNBytes(s, n):
	b = s.encode('utf8')
	if len(b) > n:
		b = b[0:n]
	elif len(b) < n:
		i = 0
		bz = i.to_bytes((n - len(b)), byteorder='little')
		b += bz
	if len(b) != 16:
		print('Error1')
	return b

f = open(EXPORT_FILE, 'wb')

# Magic
writeDWord(f, 0x1a98fd34)

# Scene
writeFloat(f, AMBIENT[0])
writeFloat(f, AMBIENT[1])
writeFloat(f, AMBIENT[2])

writeFloat(f, CLEAR_COLOUR[0])
writeFloat(f, CLEAR_COLOUR[1])
writeFloat(f, CLEAR_COLOUR[2])

objects = []
lights = bpy.data.lights

for obj in bpy.data.objects:
	if hasattr(obj.data, 'polygons'):
		objects.append(obj)

# assets

assetNames = []
assetNamesDataLength = 0

file_path_append = '.model'
if USING_COMPRESSED_MODELS:
	file_path_append += '.compressed'

for obj in objects:
	n = obj.name
	if len(n) >= 5 and n[-4] == '.' and n[-3:].isdigit():
		continue
	assetNames.append(n)
	assetNamesDataLength += (len((n + file_path_append).encode('utf8')) + 1 + 3) // 4

assetNames.sort()
print(assetNames)

writeDWord(f, assetNamesDataLength)
writeDWord(f, len(assetNames))
for n in assetNames:
	writeUTF8(f, n + file_path_append)


# Meshes

writeDWord(f, len(assetNames))
for i in range(len(assetNames)):
	writeDWord(f, i) # Asset index
	writeDWord(f, 0) # Read-only

# Textures
writeDWord(f, 0)

# objects

writeDWord(f, len(objects) + len(lights))

for obj in objects:
	f.write(stringToNBytes(obj.name, 16))
	print(stringToNBytes(obj.name, 16))
	

	n = obj.name # asset name (without file extension)
	if len(n) >= 5 and n[-4] == '.' and n[-3:].isdigit():
		n = n[:-4]

	writeDWord(f, 0xffffffff) # no parent
	writeDWord(f, 1) # has mesh renderer
	writeDWord(f, 0) # does not have light
	writeDWord(f, 0) # is not camera
	writeDWord(f, 0) # does not inherit parent transform
	writeMatrix(f, convertMatrix(obj.matrix_world))

	# Mesh renderer
	writeDWord(f, assetNames.index(n)) # Mesh
	for i in range(32):
		writeDWord(f, 0xffffffff) # texture
		writeDWord(f, 0xffffffff) # normal
		writeFloat(f, 0.05) # specular size
		writeFloat(f, 1.00) # specular intensity
		writeFloat(f, 0.025) # specular colourisation
		writeDWord(f, 1 if USE_FLAT_SHADING else 0)

# lights

for obj in lights:
	f.write(stringToNBytes(obj.name, 16))

	writeDWord(f, 0xffffffff) # parent
	writeDWord(f, 0) # does not have mesh renderer
	writeDWord(f, 1) # has light
	writeDWord(f, 0) # is not camera
	writeDWord(f, 0) # does not inherit parent transform
	writeMatrix(f, convertMatrix(bpy.data.objects[obj.name].matrix_world @ rotate_light))	

	if obj.type == 'POINT':
		writeDWord(f, 0)
	elif obj.type == 'SPOT':
		writeDWord(f, 1)
	else: # Directional
		writeDWord(f, 2)

	writeFloat(f, obj.color[0]*obj.energy)
	writeFloat(f, obj.color[1]*obj.energy)
	writeFloat(f, obj.color[2]*obj.energy)

	writeDWord(f, 1) # cast shadows
	writeFloat(f, obj.shadow_buffer_clip_start)
	writeFloat(f, obj.shadow_cascade_max_distance)

	if obj.type == 'SPOT':
		writeFloat(f, obj.spot_size)

f.close()

print('Done.')