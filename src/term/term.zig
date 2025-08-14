const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
const os = std.os;
const win = os.windows;
const winK = win.kernel32;
const winUtil = @import("win_util.zig");
const WinInput = winUtil.Input;
const WinOutput = winUtil.Output;

/// Represents the size of a terminal in both character dimensions and pixel dimensions.
pub const TermSize = struct {
    /// terminal row as measured number of characters that fit into terminal vertically
    row: u16,
    /// Terminal col as measured number of characters that fit into a terminal horizontally
    col: u16,

    /// Terminal width, measured in pixels null in win.
    Xpixel: u16,

    /// Terminal height, measured in pixels.
    Ypixel: u16,
};
/// A raw terminal representation, you can enter terminal raw mode
/// using this struct. Raw mode is essential to create a TUI.
pub const RawTerm = struct {
    orig_termios: switch (builtin.os.tag) {
        .windows => win.DWORD,
        else => std.posix.termios,
    },

    /// The OS-specific file descriptor or file handle.
    handle: std.fs.File.Handle,

    const Self = @This();

    /// Returns to the previous terminal state
    pub fn disableRawMode(self: *Self) !void {
        switch (builtin.os.tag) {
            .windows => try self.disableRawModeWindows(),
            else => try self.disableRawModePosix(),
        }
    }
    fn disableRawModeWindows(self: *Self) !void {
        return switch (winK.GetConsoleMode(self.handle, &self.orig_termios)) {
            win.FALSE => {
                const err = winK.GetLastError();
                return win.unexpectedError(err);
            },
	    else => {},
        };
    }
    fn disableRawModePosix(self: *Self) !void {
        try posix.tcsetattr(self.handle, .FLUSH, self.orig_termios);
    }
};

/// isTerminal returns whether the given file descriptor is a terminal.
pub fn isTerminal(file: std.fs.File) bool {
    return std.posix.isatty(file.handle);
}

/// Mouse event tracking modes for terminal input handling
pub const MouseMode = packed struct {
    /// Track all mouse movement events (ESC[?1003h)
    /// Generates events for any mouse movement, even without buttons pressed
    all: bool = false,

    /// Track button events and drags (ESC[?1002h)
    /// Generates events for clicks, releases, and movement while buttons are pressed
    button: bool = false,

    /// Track basic click events only (ESC[?1000h)
    /// Generates events only for button press and release
    normal: bool = false,

    /// Enable SGR extended mouse format (ESC[?1006h)
    /// Provides better coordinate handling and click/release distinction
    // sgr: bool = false,

    const Self = @This();
    /// Convert the packed struct to a 3-bit unsigned integer
    pub fn toU3(self: Self) u3 {
        return @bitCast(self);
    }

    /// Check if no mouse tracking modes are enabled
    pub fn isDefault(self: Self) bool {
        return self.toU3() == 0;
    }

    /// Enable mouse event tracking by sending appropriate escape sequences
    /// Sends different sequences based on the enabled mode:
    /// - all: ESC[?1003h (track all movement)
    /// - button: ESC[?1002h (track button events and drags)
    /// - normal: ESC[?1000h (track basic clicks only)
    /// - default: ESC[?1003h (fallback to all mode)
    pub fn enableMouseEvent(self: Self, out_writer: anytype) !void {
        // Enable SGR format if requested
        // if (self.sgr) {
        //     try out_writer.print("\x1b[?1006h", .{});
        // }
        if (self.isDefault() or self.all) {
            try out_writer.print("\x1b[?1003h", .{});
        } else if (self.button) {
            try out_writer.print("\x1b[?1002h", .{});
        } else if (self.normal) {
            try out_writer.print("\x1b[?1000h", .{});
        }
    }

    /// Disable mouse event tracking by sending corresponding 'l' sequences
    /// Sends the disable version (h->l) of whatever mode was enabled
    pub fn disableMouseEvent(self: Self, out_writer: anytype) !void {
        if (self.isDefault() or self.all) {
            try out_writer.print("\x1b[?1003l", .{});
        } else if (self.button) {
            try out_writer.print("\x1b[?1002l", .{});
        } else if (self.normal) {
            try out_writer.print("\x1b[?1000l", .{});
        }
        // Disable SGR format if it was enabled
        // if (self.sgr) {
        //     try out_writer.print("\x1b[?1006l", .{});
        // }
    }
};
const Handel = std.fs.File.Handle;
pub fn rawMode(handel: Handel) !RawTerm {
    return switch (builtin.os.tag) {
        .windows => try rawModeWin(handel),
        else => try rawModePosix(handel),
    };
}
/// rawModePosix puts the terminal connected to the given file descriptor into raw
/// mode and returns the previous state of the terminal so that it can be
/// restored.
fn rawModePosix(fd: Handel) !RawTerm {
    const original_termios = try posix.tcgetattr(posix.STDIN_FILENO);
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

fn rawModeWin(fd: Handel) !RawTerm {
    const mode = try winUtil.getConsoleMode(fd);
    var raw = mode & ~(WinInput.enable_echo_input | WinInput.enable_processed_input | WinInput.enable_line_input);
    raw |= win.ENABLE_VIRTUAL_TERMINAL_INPUT;
    try winUtil.setConsoleMode(fd, raw);
    return .{
        .orig_termios = mode,
        .handle = fd,
    };
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
            var buf: TermSize = undefined;
            const call = posix.system.ioctl(file.handle, posix.T.IOCGWINSZ, @intFromPtr(&buf));
            break :blk switch (posix.errno(call)) {
                .SUCCESS => buf,
                else => error.IoctlError,
            };
        },
        else => error.Unsupported,
    };
}
