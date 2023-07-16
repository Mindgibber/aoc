const std = @import("std");

pub fn main() !void {
    const input = try std.fs.cwd().openFile("input/Day02", .{});
    defer input.close();
    var buf_input = std.io.bufferedReader(input.reader());
    var buffer: [4096]u8 = undefined;
    var buffered_reader = buf_input.reader();
    var total: u32 = 0;
    while (try buffered_reader.readUntilDelimiterOrEof(&buffer, '\n')) |line| {
        for (std.mem.splitScalar(u8, buf, 'x')) || {}
    }
}
