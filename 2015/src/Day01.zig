const std = @import("std");

pub fn main() !void {
    const input = try std.fs.cwd().openFile("input/Day01", .{});
    defer input.close();
    var buffer: [1024 * 20]u8 = undefined;
    _ = try input.readAll(&buffer);
    var count: i32 = 0;
    var first = true;
    for (buffer, 0..) |value, index| {
        if (count == -1 and first) {
            std.debug.print("First time: {d}\n", .{index});
            first = false;
        }
        switch (value) {
            '(' => {
                count += 1;
            },
            ')' => {
                count -= 1;
            },
            '\n' => {
                break;
            },
            else => std.debug.print("{c}", .{value}),
        }
    }
    std.debug.print("{d}\n", .{count});
}
