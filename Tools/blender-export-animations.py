# SEE blender-export.py FOR INSTRUCTIONS

ANIMATION_EXPORT_FILE = 'minotaur_walk.anim'

import bpy
import struct
import bpy_extras
from mathutils import *

def writeDWord(file, i, signed=False):
	file.write(i.to_bytes(4, byteorder='little', signed=signed))

def writeByte(file, i, signed=False):
		file.write(i.to_bytes(1, byteorder='little', signed=signed))
		
def writeFloat(file, f):
	file.write(bytearray(struct.pack("f", f)))

def writeMatrix(file, m):
	for i in range(4):
		for j in range(4):
			writeFloat(file, m[j][i])

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

file = open(ANIMATION_EXPORT_FILE, 'wb')

def main():	
	global file
	
	sce = bpy.context.scene
	
	writeDWord(file, 0xee334507)
	numberOfFrames = 1 + sce.frame_end - sce.frame_start
	writeDWord(file, numberOfFrames)
	writeDWord(file, int(1000000 / sce.render.fps))
	
	
	# coordinateConversion: Blender <-> OpenGL coordinate system
		
	toOpenGLCoords = Matrix()
	
	# y,z = z,-y

	toOpenGLCoords[1][1] = 0.0
	toOpenGLCoords[1][2] = 1.0
	toOpenGLCoords[2][1] = -1.0
	toOpenGLCoords[2][2] = 0.0

	toBlenderCoords = toOpenGLCoords.inverted()

	
	
	class BoneAnim:
		pass
	
	bones = []
	
	i = 0
	for obj in bpy.data.objects:
		if hasattr(obj.data, 'bones') and hasattr(obj, 'pose') and obj.pose != None:
			for b in obj.data.bones:
				bone = BoneAnim()
				bone.index = i
				bone.matrices = [None] * numberOfFrames
				bone.matrices_pre_mul = [None] * numberOfFrames
				bone.name = b.name
				bone.isAnimated = False
				bones.append(bone)
				i += 1
	
	if len(bones) < 1:
		print('No bones!')
		return
	
	for f in range(numberOfFrames):
		sce.frame_set(f + sce.frame_start)
		i = 0
		for obj in bpy.data.objects:
			if hasattr(obj.data, 'bones') and hasattr(obj, 'pose') and obj.pose != None:	
				for bone in obj.data.bones:
					pbone = obj.pose.bones[bone.name]

					editModeTailTransform = obj.matrix_world @ bone.matrix_local
					poseModeTailTransform = obj.matrix_world @ pbone.matrix

					bones[i].isAnimated = editModeTailTransform != poseModeTailTransform

					m_pre_mul = toOpenGLCoords @ poseModeTailTransform @ editModeTailTransform.inverted() @ toBlenderCoords
				
					bones[i].matrices[f] = Matrix()
					bones[i].matrices_pre_mul[f] = m_pre_mul
					i += 1
			
			
	# Check for bones which are not modified
		
	animatedBones = [x for x in bones if x.isAnimated]
				
	writeDWord(file, len(animatedBones))
	print(len(animatedBones), 'animated bones')
	
	for b in animatedBones:
		writeUTF8(file, b.name)
	
	for f in range(numberOfFrames):
		for b in animatedBones:
			writeMatrix(file, b.matrices[f])
	
	for f in range(numberOfFrames):
		for b in animatedBones:
			writeMatrix(file, b.matrices_pre_mul[f])
	
	print('Animation export complete\n')
main()

file.close()


