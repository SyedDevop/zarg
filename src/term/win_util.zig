const std = @import("std");
const os = std.os;
const win = os.windows;
const winK = win.kernel32;

// input
pub const ENABLE_PROCESSED_INPUT = 0x0001;
pub const ENABLE_LINE_INPUT = 0x0002;
pub const ENABLE_ECHO_INPUT = 0x0004;
pub const ENABLE_VIRTUAL_TERMINAL_INPUT = 0x0200;
// OutPUT
pub const ENABLE_PROCESSED_OUTPUT = 0x0001;
pub const ENABLE_WRAP_AT_EOL_OUTPUT = 0x0002;
pub const ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004;
pub const DISABLE_NEWLINE_AUTO_RETURN = 0x0008;

pub fn getConsoleMode(handle: win.HANDLE) !win.DWORD {
    var mode: win.DWORD = undefined;
    if (winK.GetConsoleMode(handle, &mode) == 0) switch (winK.GetLastError()) {
        else => |e| return win.unexpectedError(e),
    };
    return mode;
}
pub fn setConsoleMode(handle: win.HANDLE, mode: win.DWORD) !void {
    if (winK.SetConsoleMode(handle, mode) == 0) switch (winK.GetLastError()) {
        else => |e| return win.unexpectedError(e),
    };
}
