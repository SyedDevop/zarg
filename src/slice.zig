const std = @import("std");

pub const RawArgs = std.ArrayList([]const u8);

/// Safely removes up to `count` elements from `xs`, starting at `start_index`.
///
/// If the specified range would exceed the bounds of the array, it removes only the
/// available number of elements from `start_index` to the end.
///
/// - If `start_index` is out of bounds (greater than or equal to `xs.items.len`), no elements are removed.
/// - If `count` is too large to fit within the array, it is clamped to the maximum valid range.
///
/// This is a safe variant of `removeRange` that avoids out-of-bounds access.
///
/// Example:
/// ```zig
/// // Given an array [a, b, c, d], calling removeRangeSafe(&xs, 2, 5)
/// // will remove [c, d], not error out.
/// ```
pub fn removeRangeSafe(xs: *RawArgs, start_index: usize, count: usize) !void {
    if (start_index >= xs.items.len) return; // nothing to remove
    const available = xs.items.len - start_index;
    try removeRange(xs, start_index, @min(count, available));
}

/// Removes a range of elements from `xs`, starting at `start_index` and removing `count` elements.
///
/// This version removes exactly `count` elements.
///
/// Example: removeRange(&xs, 2, 3) will remove elements at indices 2, 3, and 4 (three elements total).
pub fn removeRange(xs: *RawArgs, start_index: usize, count: usize) !void {
    for (0..count) |_| {
        _ = xs.orderedRemove(start_index);
    }
}

/// Safely removes `count + 1` elements from `xs`, starting at `start_index`.
///
/// This is a safe variant of `removeRangeInclusive` that avoids out-of-bounds access.
///
/// from `start_index` up to and including `start_index + count`. If the requested
/// range exceeds the bounds of the array, it clamps the removal to the valid portion.
///
/// - Does nothing if `start_index` is out of bounds.
/// - Guarantees no out-of-bounds access.
///
/// Example:
/// ```zig
/// // Given [a, b, c, d], removeRangeInclusiveSafe(&xs, 2, 2)
/// // attempts to remove [c, d] (indices 2, 3, 4), but only [c, d] are removed.
/// ```
pub fn removeRangeInclusiveSafe(xs: *RawArgs, start_index: usize, count: usize) !void {
    if (start_index >= xs.items.len) return; // nothing to remove
    const available = (xs.items.len - start_index) - 1; // -1 because we are inclusive
    try removeRangeInclusive(xs, start_index, @min(count, available));
}

/// Removes a range of elements from `xs`, starting at `start_index` and removing `count + 1` elements.
///
/// This version includes the end index in the removal. That is, it removes from `start_index` to `start_index + count`, inclusive.
///
/// Example: removeRangeInclusive(&xs, 2, 3) will remove elements at indices 2, 3, 4, and 5 (four elements total).
pub fn removeRangeInclusive(xs: *RawArgs, start_index: usize, count: usize) !void {
    for (0..count + 1) |_| {
        _ = xs.orderedRemove(start_index);
    }
}

pub fn shift(comptime T: type, xs: *[]T) !T {
    if (xs.len == 0) {
        return error.EmptySlice;
    }
    const first = xs.*[0];
    xs.ptr += 1;
    xs.len -= 1;
    return first;
}

test "removeRange removes correct elements" {
    const allocator = std.testing.allocator;
    var args = RawArgs.empty;
    defer args.deinit(allocator);

    try args.append(allocator, "arg0");
    try args.append(allocator, "arg1");
    try args.append(allocator, "arg2");
    try args.append(allocator, "arg3");
    try args.append(allocator, "arg4");

    // Remove elements from index 1 (arg1, arg2)
    try removeRange(&args, 1, 2);

    try std.testing.expectEqual(@as(usize, 3), args.items.len);
    try std.testing.expectEqualStrings("arg0", args.items[0]);
    try std.testing.expectEqualStrings("arg3", args.items[1]);
    try std.testing.expectEqualStrings("arg4", args.items[2]);
}

test "removeRangeSafe" {
    const allocator = std.testing.allocator;
    var args = RawArgs.empty;
    defer args.deinit(allocator);
    try args.appendSlice(allocator, &.{ "arg0", "arg1", "arg2", "arg3", "arg4" });
    // Remove elements from index 1 (arg1, arg2)
    try removeRangeSafe(&args, 3, 3);
    try std.testing.expectEqual(@as(usize, 3), args.items.len);
    try std.testing.expectEqualStrings("arg0", args.items[0]);
    try std.testing.expectEqualStrings("arg1", args.items[1]);
    try std.testing.expectEqualStrings("arg2", args.items[2]);
}

test "removeRangeInclusive" {
    const allocator = std.testing.allocator;
    var args = RawArgs.empty;
    defer args.deinit(allocator);
    try args.appendSlice(allocator, &.{ "arg0", "arg1", "arg2", "arg3", "arg4" });
    // Remove elements from index 1 (arg1, arg2)
    try removeRangeInclusive(&args, 2, 2);
    try std.testing.expectEqual(@as(usize, 2), args.items.len);
    try std.testing.expectEqualStrings("arg0", args.items[0]);
    try std.testing.expectEqualStrings("arg1", args.items[1]);
}

test "removeRangeInclusiveSafe" {
    const allocator = std.testing.allocator;
    var args = RawArgs.empty;
    defer args.deinit(allocator);
    try args.appendSlice(allocator, &.{ "arg0", "arg1", "arg2", "arg3", "arg4" });
    // Remove elements from index 1 (arg1, arg2)
    try removeRangeInclusiveSafe(&args, 2, 3);
    try std.testing.expectEqual(@as(usize, 2), args.items.len);
    try std.testing.expectEqualStrings("arg0", args.items[0]);
    try std.testing.expectEqualStrings("arg1", args.items[1]);
}
