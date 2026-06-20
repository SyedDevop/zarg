const std = @import("std");
const eql = std.mem.eql;

/// Logs a message to stderr with the source location of the call site.
///
/// - `msg`: The log message to display.
/// - `loc`: A `@SourceLocation` value, typically provided by `@src()`, indicating
///          where in the source code the log call occurred.
pub fn logLocMessage(msg: []const u8, loc: std.builtin.SourceLocation) void {
    std.debug.print("{s}:{d}:{d}: {s}\n", .{ loc.file, loc.line, loc.column, msg });
}

/// A list of string values that are considered "truthy" when parsed.
/// Useful for handling user input or environment variables.
pub const TRUTHY_STRINGS = [_][]const u8{
    "true", "t",
    "yes",  "y",
    "1",    "enable",
};

/// Returns `true` if the given string matches any known truthy value.
///
/// This function performs an exact, case-sensitive match.
/// If you need case-insensitive matching, convert the input beforehand.
///
/// NOTE: To see the complete list of supported truthy values,
/// check `TRUTHY_STRINGS`.
pub fn isTruthyStr(v: []const u8) bool {
    for (TRUTHY_STRINGS) |s| if (eql(u8, v, s)) return true;
    return false;
}
