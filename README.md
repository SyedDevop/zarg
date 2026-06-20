# zarg

<!--toc:start-->

- [zarg](#zarg)
  - [Installation](#installation)
  - [Usage](#usage)
  <!--toc:end-->

**_zarg_** is pure Zig library for low-level terminal manipulation.

> [!WARNING]
> This library is a WIP and may have breaking changes and bugs.
> Tested with zig version `0.16.0`

## Installation

First we add the library as a dependency in our `build.zig.zon` file with the
following command.

```bash
zig fetch --save git+https://github.com/SyedDevop/zarg
```

And we add it to `build.zig` file.

```zig
const zarg_dep = b.dependency("zarg", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("zarg", zarg_dep.module("zarg"));
```

## Usage

Now we can use the library in our code.

```zig
const std = @import("std");
const mibu = @import("zarg");
const color = zarg.color;

pub fn main() void {
    std.debug.print("{s}Hello World in purple!\n", .{});
}
```
