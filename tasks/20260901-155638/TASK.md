# CmdEnum and commands list mismatch is not caught at compile time

- STATUS: OPEN
- PRIORITY: 100
- TAGS: bug

---

`zarg.Cli.Cmd(Cmds)` derives the set of available commands from the CmdEnum, but
the corresponding command definitions must be supplied separately via CMD_LIST.
There is currently no compile-time check that these two stay consistent — a
variant present in Cmds but absent from CMD_LIST (or the reverse) goes
undetected until runtime, if it's caught at all.

```zig
pub const Cmds = enum {
    root,
    init,
    ls,
    new,
    summary,
};

pub const CmdType = zarg.Cli.Cmd(Cmds);

pub const CMD_LIST = [_]CmdType{
    .{ .name = .root },
    .{ .name = .init },
    .{ .name = .ls },
    .{ .name = .new },
    // .summary is missing
};
```
