const builtin = @import("builtin");
const std = @import("std");

extern fn InitializeConditionVariable(*c_void) void;
extern fn SleepConditionVariableCS(*c_void, *c_void, u32) void;
extern fn WakeConditionVariable(*c_void) void;

extern fn InitializeCriticalSection(*c_void) void;
extern fn EnterCriticalSection(*c_void) void;
extern fn LeaveCriticalSection(*c_void) void;
extern fn DeleteCriticalSection(*c_void) void;

pub const ConditionVariable = switch (builtin.os) {
    // builtin.Os.linux => struct {
        // TODO
    // },
    builtin.Os.windows => struct {
        mutex: [40]u8, // 40-byte mutex struct.
        condition_variable: u64,

        need_to_wake: bool,

        pub fn init() ConditionVariable {
            var c: ConditionVariable = undefined;
            c.need_to_wake = false;
            InitializeCriticalSection(&c.mutex);
            InitializeConditionVariable(&c.condition_variable);
            return c;
        }

        // Puts current thread to sleep until another thread calls notify()
        pub fn wait(self: *ConditionVariable) void {
            EnterCriticalSection(&self.mutex);
            if(!self.need_to_wake) {
                // Releases the lock and sleeps
                SleepConditionVariableCS(&self.condition_variable, &self.mutex, 0xffffffff);
            }
            self.need_to_wake = false;
            LeaveCriticalSection(&self.mutex);
        }

        // Wake up the thread that has called wait()
        pub fn notify(self: *ConditionVariable) void {
            EnterCriticalSection(&self.mutex);
            self.need_to_wake = true;
            WakeConditionVariable(&self.condition_variable);
            LeaveCriticalSection(&self.mutex);
        }

        pub fn free(self: *ConditionVariable) void {
            DeleteCriticalSection(&self.mutex);
        }
    },
    else => struct {
        // Inefficient implementation using an atomic integer and sleeping

        need_to_wake: std.atomic.Int(u32),

        pub fn init() ConditionVariable {
            return ConditionVariable {
                .need_to_wake = std.atomic.Int(u32).init(0),
            };
        }

        pub fn wait(self: *ConditionVariable) void {
            while(self.need_to_wake.get() == 0) {
                std.time.sleep(1000*1000*5); // 5ms
            }
        }

        pub fn notify(self: *ConditionVariable) void {
            self.need_to_wake.set(1);
        }

        pub fn free(self: *ConditionVariable) void {

        }
    },
};
