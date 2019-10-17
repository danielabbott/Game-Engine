# Custom file format for models
All fields are little endian.

ux – Unsigned x-bit integer

ix – Signed x-bit integer

float – 32-bit IEEE 754 floating point value

boolean – 32-bit true/false variable, value may only be 1 (true) or 0 (false)

ASCII string – null-terminated string using the 7-bit UTF8-compatible ASCII character set. MUST have padding after to round to 4 bytes to keep alignment.

UTF8 string – UTF8-encoded string using the unicode character set. 
Characters are either 1, 2, 3, or 4 bytes long. 
MUST have padding after to round to 4 bytes to keep alignment.
Starts with a u8 for string length (0 is valid - it means the string is empty)
        
Vec[x] – x-length packed array of floats


Field Name | Field Type | Description
---------- | ---------- | -----------
Magic | u32 | 0xaaeecdbb
Indices Count | u32 | If 0 then glDrawArrays is used.
Vertex attributes | 32 | See Vertex Attributes section below
isInterleaved | boolean (u32) | If true the vertex data is grouped by vertex, if false the data is grouped by attribute
Vertex count | u32 | If >65536, indices are stored as u32 instead of u16
Vertex Data |  | 
Index Data |  | 
 |  | 		
Region Count | u32 | 	
Region[i].firstIndex | u32 | First index at which this material takes effect
Region[i].indexVertexCount | u32 | Number of indices/vertices for which this material applies. Counts vertices if index_count == 0.
Region[i].colour | [3]f32 | 	
Region[i].materialName | UTF8String | 
 |  | 		
Bone Count | u32 | 
bones[i].head | vec3 | Start position of bone in 3D space
bones[i].tail | vec3 | End position of bone in 3D space
bones[i].parent | int | Index into bones array. Negative value for root bone(s)
bones[i].name | UTF8string | 


## Vertex Attributes
VERTEX_COORDINATES = 1 << 0    (float x,y,z)

COLOUR = 1 << 1 (u32, rgba 4xu8) (unimplemented in blender export script)

TEXTURE_COORDINATES = 1 << 2   (u16,u16  normalised)

NORMALS = 1 << 3   (i32, z10y10x10 lsb→msb-2) The two most significant bits are not used.

BONE_INDICES= 1 << 4 (u8,u8,u8,u8) Indices into bones array. Requires BONE_WEIGHTS.

VERTEX_WEIGHTS = 1 << 5 (u8,u8,u8,u8) NormalisedFloats, use 4 weights of 0 for a static vertex. Requires BONE_INDICES.

TANGENTS = 1 << 6 (i32, z10y10x10 lsb→msb-2) The two most significant bits are not used. Requires NORMALS.

Each attribute type must be used no more than once.