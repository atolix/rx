const std = @import("std");
const rule_types = @import("../rule.zig");

pub const Result = rule_types.RuleResult;

/// Removes empty lines from the beginning of the file.
pub fn apply(allocator: std.mem.Allocator, source: []const u8) !Result {
    var index: usize = 0;

    while (index < source.len) {
        var line_end = index;
        while (line_end < source.len and source[line_end] != '\n') : (line_end += 1) {}
        const line = source[index..line_end];

        var blank = true;
        for (line) |ch| {
            if (ch != ' ' and ch != '\t' and ch != '\r') {
                blank = false;
                break;
            }
        }
        if (!blank) break;

        if (line_end < source.len) {
            index = line_end + 1;
        } else {
            index = line_end;
        }
    }

    if (index == 0) {
        return Result{ .changed = false, .buffer = @constCast(source) };
    }

    const buffer = try allocator.alloc(u8, source.len - index);
    std.mem.copyForwards(u8, buffer, source[index..]);
    return Result{ .changed = true, .buffer = buffer };
}

test "leading empty lines removes blank lines at start of file" {
    const allocator = std.testing.allocator;
    const input = "\n\nclass User\nend\n";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(result.changed);
    try std.testing.expectEqualStrings("class User\nend\n", result.buffer);
}

test "leading empty lines removes whitespace only lines at start" {
    const allocator = std.testing.allocator;
    const input = "  \n\t\nclass User\n";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(result.changed);
    try std.testing.expectEqualStrings("class User\n", result.buffer);
}

test "leading empty lines keeps clean file unchanged" {
    const allocator = std.testing.allocator;
    const input = "class User\nend\n";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(!result.changed);
    try std.testing.expectEqualStrings(input, result.buffer);
}
