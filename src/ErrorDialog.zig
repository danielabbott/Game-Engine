const builtin = @import("builtin");
const std = @import("std");

extern fn MessageBoxA(
  hWnd: usize,
  lpText: [*c]const u8,
  lpCaption: [*c]const u8,
  uType: u32
) void;

extern fn strlen(s: [*]const u8) usize;
pub fn showErrorMessageDialog(title: [*c]const u8, text: [*c]const u8) void {    
    if(builtin.os.tag == builtin.Os.Tag.windows) {
        MessageBoxA(0, text, title, 0x10);
    }
    else {
        const titleLen = strlen(title);
        const textLen = strlen(text);
        std.debug.warn("({}) {}\n", .{title[0..titleLen], text[0..textLen]});
    }
}
