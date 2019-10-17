# Custom file format for zstd-compressed data

Field Name | Field Type | Description
---------- | ---------- | -----------
Magic | u96 |	0x88, 0x7c, 0x77, 0x6a, 0xee, 0x55, 0xdd, 0xcc, 0x37, 0x9a, 0x8b, 0xef
Data original size | u32 | Size of uncompressed data. If 0 then the data is stored uncompressed.
Data | |	
