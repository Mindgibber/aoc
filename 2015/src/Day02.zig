const std = @import("std");

pub fn main() !void {
    const input = try std.fs.cwd().openFile("input/Day02", .{});
    defer input.close();
    var buf_input = std.io.bufferedReader(input.reader());
    var buffer: [4096]u8 = undefined;
    var buffered_reader = buf_input.reader();
    var total: u32 = 0;
    const Rect = struct { l: u32, w: u32, h: u32 };
    while (try buffered_reader.readUntilDelimiterOrEof(&buffer, '\n')) |line| {
        var iter = std.mem.splitScalar(u8, line, 'x');
        const rect: Rect = .{
            .l = try std.fmt.parseInt(u32, iter.next().?, 10),
            .w = try std.fmt.parseInt(u32, iter.next().?, 10),
            .h = try std.fmt.parseInt(u32, iter.next().?, 10),
        };
        const slack = @min(@min((rect.l * rect.w), (rect.w * rect.h)), (rect.h * rect.l));
        const surface_area = (2 * (rect.l * rect.w)) + (2 * (rect.w * rect.h)) + (2 * (rect.h * rect.l));
        total = total + slack + surface_area;

        //std.debug.print("l: {s}rect w: {s} h: {s}\n", rect);
    }
    std.debug.print("Total: {d}\n", .{total});
}
