# Custom file format RGBA10A2 Image files (.rgb10a2)

Field Name | Field Type | Description
---------- | ---------- | -----------
Magic | u64 | 0x00, 0x72, 0x67, 0x62, 0x31, 0x30, 0x61, 0x32
width | u32 | In pixels
height | u32 | In pixels
Data (uncompressed) |  | Size = width*height*4.

