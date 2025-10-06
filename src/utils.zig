const std = @import("std");

/// Logs a message to stderr with the source location of the call site.
///
/// - `msg`: The log message to display.
/// - `loc`: A `@SourceLocation` value, typically provided by `@src()`, indicating
///          where in the source code the log call occurred.
pub fn logLocMessage(msg: []const u8, loc: std.builtin.SourceLocation) void {
    var buf: [1024]u8 = undefined;
    var stderr_w = std.fs.File.stderr().writer(&buf);
    const stderr = &stderr_w.interface;
    defer stderr.flush() catch {};
    stderr.print("{s}:{d}:{d}: {s}\n", .{ loc.file, loc.line, loc.column, msg }) catch {};
}
