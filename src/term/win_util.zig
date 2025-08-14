const std = @import("std");
const os = std.os;
const win = os.windows;
const winK = win.kernel32;

pub const Input = enum(u32) {
    enable_processed_input = 0x0001,
    enable_line_input = 0x0002,
    enable_echo_input = 0x0004,
    enable_virtual_terminal_input = 0x0200,
};

pub const Output = enum(u32) {
    enable_processed_output = 0x0001,
    enable_wrap_at_eol_output = 0x0002,
    enable_virtual_terminal_processing = 0x0004,
    disable_newline_auto_return = 0x0008,
};

pub fn getConsoleMode(handle: win.HANDLE) !win.DWORD {
    var mode: win.DWORD = undefined;
    switch (winK.GetConsoleMode(handle, &mode)) {
        win.TRUE => return mode,
        win.FALSE => {
            const err = winK.GetLastError();
            return win.unexpectedError(err);
        },
    }
}
pub fn setConsoleMode(handle: win.HANDLE, mode: win.DWORD) !void {
    switch (winK.SetConsoleMode(handle, &mode)) {
        win.TRUE => {},
        win.FALSE => {
            const err = winK.GetLastError();
            return win.unexpectedError(err);
        },
    }
}
