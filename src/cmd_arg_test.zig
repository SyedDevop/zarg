const std = @import("std");
const Cmd = @import("cmd.zig");

test "check for arg equality" {
    const arg1 = Cmd.Arg{ .long = "view", .short = 'v', .info = "", .value = .{ .str = null } };
    const arg2 = Cmd.Arg{ .long = "view", .short = 'v', .info = "", .value = .{ .str = null } };
    const arg3 = Cmd.Arg{ .long = "list", .short = 'l', .info = "", .value = .{ .str = "game" } };
    const arg4 = Cmd.Arg{ .short = 'l', .info = "", .value = .{ .str = "game" } };
    const arg5 = Cmd.Arg{ .long = "list", .info = "", .value = .{ .str = "game" } };

    try std.testing.expect(arg1.isEqual(arg2) == true);
    try std.testing.expect(arg1.isEqual(arg3) == false);
    try std.testing.expect(arg3.isEqual(arg4) == true);
    try std.testing.expect(arg3.isEqual(arg5) == true);
    try std.testing.expect(arg4.isEqual(arg5) == false);
}
