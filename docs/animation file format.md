# Custom file format for skeletal animations

Field Name | Field Type | Description
---------- | ---------- | -----------
Magic | u32	| 0xee334507
Frame Count | u32 | Length of this animation in frames
Frame duration | u32 | In microseconds. 16667 for 60fps.
Bone Count | u32 | 
boneNames [Bone Count] | UTF8[]	| So that animations can be applied to any model (assuming bone names match up)
matrices_relative [FrameCount][Bone Count] | mat4[][] | A matrix for each bone is stored for every frame. The matrix represents a transformation that takes a bone from its default position (where it is shown in edit mode in Blender) to its position for this frame (relative to the parent bone).
matrices_absolute[FrameCount][Bone Count] |	mat4[][] |The same as above but stores the final transformation of each bone. Using this data directly saves multiplying matrices each frame if the animation is used directly (not mixed with other animations).

