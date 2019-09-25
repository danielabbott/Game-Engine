// Untested
pub fn strlen(s: []const u8) u32 {
    @setRuntimeSafety(false);
    var i: usize = 0;
    while (i < s.len and s[i] != 0) {
        i += 1;
    }
    return i;
}
