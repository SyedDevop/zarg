const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
const os = std.os;
const win = os.windows;
const winK = win.kernel32;

/// Represents the size of a terminal in both character dimensions and pixel dimensions.
pub const TermSize = struct {
    /// Terminal col as measured number of characters that fit into a terminal horizontally
    col: u16,
    /// terminal row as measured number of characters that fit into terminal vertically
    row: u16,

    /// Terminal width, measured in pixels null in win.
    Xpixel: ?u16 = null,

    /// Terminal height, measured in pixels.
    Ypixel: ?u16 = null,
};
const WindowsConsoleMode = struct {
    stdin: u32,
    stdout: u32,

    const Input = enum(u32) {
        enable_processed_input = 0x0001,
        enable_line_input = 0x0002,
        enable_echo_input = 0x0004,
        enable_virtual_terminal_input = 0x0200,
    };

    const Output = enum(u32) {
        enable_processed_output = 0x0001,
        enable_wrap_at_eol_output = 0x0002,
        enable_virtual_terminal_processing = 0x0004,
        disable_newline_auto_return = 0x0008,
    };
};
/// A raw terminal representation, you can enter terminal raw mode
/// using this struct. Raw mode is essential to create a TUI.
pub const RawTerm = struct {
    orig_termios: std.posix.termios,

    /// The OS-specific file descriptor or file handle.
    handle: os.linux.fd_t,

    const Self = @This();

    /// Returns to the previous terminal state
    pub fn disableRawMode(self: *Self) !void {
        try posix.tcsetattr(self.handle, .FLUSH, self.orig_termios);
    }
};

/// isTerminal returns whether the given file descriptor is a terminal.
pub fn isTerminal(file: std.fs.File) bool {
    return std.posix.isatty(file.handle);
}

/// rawModePosix puts the terminal connected to the given file descriptor into raw
/// mode and returns the previous state of the terminal so that it can be
/// restored.
pub fn rawModePosix(fd: posix.fd_t) !RawTerm {
    const original_termios = try std.posix.tcgetattr(fd);
    var raw = original_termios;

    raw.iflag.IGNBRK = false;
    raw.iflag.BRKINT = false;
    raw.iflag.PARMRK = false;
    raw.iflag.ISTRIP = false;
    raw.iflag.INLCR = false;
    raw.iflag.IGNCR = false;
    raw.iflag.ICRNL = false;
    raw.iflag.IXON = false;

    raw.oflag.OPOST = false;

    raw.lflag.ECHO = false;
    raw.lflag.ECHONL = false;
    raw.lflag.ICANON = false;
    raw.lflag.ISIG = false;
    raw.lflag.IEXTEN = false;

    raw.cflag.CSIZE = .CS8;
    raw.cc[@intFromEnum(posix.V.MIN)] = 1;
    raw.cc[@intFromEnum(posix.V.TIME)] = 0;
    try posix.tcsetattr(fd, .FLUSH, raw);
    return .{
        .orig_termios = original_termios,
        .handle = fd,
    };
}

pub fn rawModeWin(fd: posix.fd_t) !void {
    if (0 == 0) return error.NotImplemented;
    var mode_stdout: win.DWORD = 0;
    switch (winK.GetConsoleMode(fd, &mode_stdout)) {
        win.TRUE => {},
        else => error.Unexpected,
    }
}

/// getSize returns the visible dimensions of the given terminal.
///
/// These dimensions don't include any scrollback buffer height.
pub fn getSize(file: std.fs.File) !?TermSize {
    return switch (builtin.os.tag) {
        .windows => blk: {
            var buf: os.windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
            break :blk switch (os.windows.kernel32.GetConsoleScreenBufferInfo(
                file.handle,
                &buf,
            )) {
                os.windows.TRUE => TermSize{
                    .col = @intCast(buf.srWindow.Right - buf.srWindow.Left + 1),
                    .row = @intCast(buf.srWindow.Bottom - buf.srWindow.Top + 1),
                    .Xpixel = 0,
                    .Ypixel = 0,
                },
                else => error.Unexpected,
            };
        },
        .linux, .macos => blk: {
            var buf: posix.system.winsize = undefined;
            break :blk switch (std.posix.errno(
                std.posix.system.ioctl(
                    file.handle,
                    std.posix.T.IOCGWINSZ,
                    @intFromPtr(&buf),
                ),
            )) {
                .SUCCESS => TermSize{
                    .col = buf.ws_col,
                    .row = buf.ws_row,
                    .Xpixel = buf.ws_xpixel,
                    .Ypixel = buf.ws_ypixel,
                },
                else => error.IoctlError,
            };
        },
        else => error.Unsupported,
    };
}
