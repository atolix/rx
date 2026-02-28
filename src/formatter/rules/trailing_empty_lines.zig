const std = @import("std");
const rule_types = @import("../rule.zig");

pub const Result = rule_types.RuleResult;

/// Ensures files do not end with more than one trailing newline.
pub fn apply(allocator: std.mem.Allocator, source: []const u8) !Result {
    if (source.len == 0) {
        return Result{ .changed = false, .buffer = @constCast(source) };
    }

    var newline_count: usize = 0;
    var idx = source.len;
    while (idx > 0 and source[idx - 1] == '\n') : (idx -= 1) {
        newline_count += 1;
    }

    if (newline_count <= 1) {
        return Result{ .changed = false, .buffer = @constCast(source) };
    }

    const keep_len = source.len - (newline_count - 1);
    const buffer = try allocator.alloc(u8, keep_len);
    std.mem.copyForwards(u8, buffer, source[0..keep_len]);
    return Result{ .changed = true, .buffer = buffer };
}

test "trailing empty lines removes extra blank lines at end of file" {
    const allocator = std.testing.allocator;
    const input = "class User\nend\n\n\n";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(result.changed);
    try std.testing.expectEqualStrings("class User\nend\n", result.buffer);
}

test "trailing empty lines keeps single final newline" {
    const allocator = std.testing.allocator;
    const input = "class User\nend\n";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(!result.changed);
    try std.testing.expectEqualStrings(input, result.buffer);
}

test "trailing empty lines keeps file without trailing newline" {
    const allocator = std.testing.allocator;
    const input = "class User\nend";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(!result.changed);
    try std.testing.expectEqualStrings(input, result.buffer);
}
