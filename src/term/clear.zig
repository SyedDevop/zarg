//! Clear screen.
//! API: small, self-documenting functions that write the corresponding
//! CSI + sequence to the provided writer.
//! Note: most "clear" operations DO NOT move the cursor. See `clearAllAndMoveTop`.

const std = @import("std");
const Writer = std.Io.Writer;

/// ANSI / terminal clear sequences (strings do NOT include the CSI prefix).
/// These are the final fragments you append after the common CSI (`"\x1b["`).
pub const csi = "\x1b[";

/// clear from cursor to end of screen
pub const screen_from_cursor = "0J";
/// clear from beginning of screen to cursor
pub const screen_to_cursor = "1J";
/// clear entire screen
pub const screen_full = "2J";

/// clear from cursor to end of line
pub const line_from_cursor = "0K";
/// clear from beginning of line to cursor
pub const line_to_cursor = "1K";
/// clear entire line
pub const line_all = "2K";

/// A handy "backspace + space + backspace" sequence to erase the previous character.
pub const left_char_erase = "\x08 \x08";

/// Move cursor to top-left (row 1, column 1). Use with CSI prefix.
pub const move_cursor_top = "H";

/// Clear from cursor until end of screen
pub inline fn screenFromCursor(writer: *Writer) !void {
    return std.fmt.format(writer, csi ++ screen_from_cursor, .{});
}

/// Clear from cursor to beginning of screen
pub inline fn screenToCursor(writer: *Writer) !void {
    return std.fmt.format(writer, csi ++ screen_to_cursor, .{});
}

/// Clear the left character Like:'Backspace'
pub inline fn clearLeftChar(writer: *Writer) !void {
    return writer.writeAll("\x08 \x08");
}

/// Clear Full screen
pub inline fn full(writer: *Writer) !void {
    return writer.writeAll(csi ++ screen_full);
}

/// Clear Full Screen and Move cursor to top-left (row 1, column 1).
pub inline fn allMoveCurserTop(writer: *Writer) !void {
    try full(writer);
    return writer.writeAll(csi ++ move_cursor_top);
}
/// Clear from cursor to end of line
pub inline fn lineFromCursor(writer: *Writer) !void {
    return writer.writeAll(csi ++ line_from_cursor);
}

/// Clear start of line to the cursor
pub inline fn lineToCursor(writer: *Writer) !void {
    return writer.writeAll(csi ++ line_to_cursor);
}

/// Clear entire line
pub inline fn entireLine(writer: *Writer) !void {
    return writer.writeAll(csi ++ line_all);
}
