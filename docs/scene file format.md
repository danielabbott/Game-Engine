# Custom file format for mesh animations

Field Name | Field Type | Description
---------- | ---------- | -----------
Magic | u64 | 0x1a98fd34
Ambient light | [3]f32 | 	
Clear colour | [3]f32 | Passed to glClearColor. Sets background of scene
Asset names data length | u32 | For skipping past asset list when parsing file
No. Asset names | u32 | 
Asset Names[No. Asset names ^] | []UTF8 | 
No. Meshes | u32 | 
  Mesh.AssetIndex | u32 | Index into UTF8[] asset names
  Mesh.Modifiable | bool (u32) | 	
No. Textures | u32 | 	
Textures[i]: |  | 		
  Texture.Asset index | u32 | 	
  Texture.Modifiable | bool(u32) | 	
  Texture.SmoothWhenMagnified | bool(u32) | GL_NEAREST / GL_LINEAR
  Texture.MinFilter | u32 | See Texture Filtering section below
No. Game Objects | u32 | 
  Object.Name | [16]u8 | 	
  Object.Parent | u32 | Index into this list of game objects. Can only point to an object that has a lower index than this object.
  Object.HasMeshRenderer | bool(u32) | 	
  Object.HasLight | bool(u32) | 	
  Not used | u32 | 
  Object.InheritsParentTransform | bool(u32) | 	
  Object.Transform | Mat4x4(f32) | 	Relative to parent (unless InheritsParentTransform is false)
  IF HAS MESH RENDERER: | ~~~~ | ~~~~
    -> Mesh Index | u32 | 
    -> Materials[8]: |  | 		
      -> Material.TextureIndex | u32 | Index into textures array
      -> Material.NormalMapTextureIndex | u32 | Index into textures array
      -> Material.SpecularSize | f32 | 
      -> Material.SpecularIntensity | f32 | 
     -> Material. SpecularColourisation | f32 | 
IF HAS LIGHT: | ~~~~ | ~~~~
  -> Light type | u32 | 0 = Point, 1 = Spot, 2 = Directional
  -> Intensity/Colour | [3]f32 | light colour * light energy
  -> Cast shadows | bool(u32) | 	
  -> Clip start | f32 | For shadow maps. Make as far (high value) as possible for best shadow quality.
  -> Clip end | f32 | For shadow maps. Make as near (low value) as possible for best shadow quality
  IF LIGHT TYPE == SPOTLIGHT: | ~~~~ | ~~~~
    -> Angle | f32 | 

## Texture Filtering
0 = Nearest (GL_NEAREST)

1 = Linear (GL_LINEAR)

2 = NearestMipMapNearest (GL_NEAREST_MIPMAP_NEAREST)

3 = LinearMipMapNearest (GL_LINEAR_MIPMAP_NEAREST)

4 = NearestMipMapLinear (GL_NEAREST_MIPMAP_LINEAR)

5 = LinearMipMapLinear (GL_LINEAR_MIPMAP_LINEAR)
