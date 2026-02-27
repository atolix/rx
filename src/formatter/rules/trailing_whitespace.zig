const std = @import("std");
const rule_types = @import("../rule.zig");

pub const Result = rule_types.RuleResult;

/// Removes trailing spaces/tabs from each line.
pub fn apply(allocator: std.mem.Allocator, source: []const u8) !Result {
    var builder = std.ArrayListUnmanaged(u8){};
    errdefer builder.deinit(allocator);

    var changed = false;
    var line_start: usize = 0;
    var i: usize = 0;

    while (i < source.len) : (i += 1) {
        if (source[i] != '\n') continue;

        const line = source[line_start..i];
        const trimmed = std.mem.trimRight(u8, line, " \t");
        if (trimmed.len != line.len) changed = true;

        try builder.appendSlice(allocator, trimmed);
        try builder.append(allocator, '\n');
        line_start = i + 1;
    }

    if (line_start < source.len) {
        const line = source[line_start..];
        const trimmed = std.mem.trimRight(u8, line, " \t");
        if (trimmed.len != line.len) changed = true;
        try builder.appendSlice(allocator, trimmed);
    }

    if (!changed and builder.items.len == source.len and std.mem.eql(u8, builder.items, source)) {
        builder.deinit(allocator);
        return Result{ .changed = false, .buffer = @constCast(source) };
    }

    return Result{
        .changed = changed or !std.mem.eql(u8, builder.items, source),
        .buffer = try builder.toOwnedSlice(allocator),
    };
}

test "trailing whitespace removes spaces and tabs before newline" {
    const allocator = std.testing.allocator;
    const input = "foo  \nbar\t\t\n";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(result.changed);
    try std.testing.expectEqualStrings("foo\nbar\n", result.buffer);
}

test "trailing whitespace removes spaces at end of file line" {
    const allocator = std.testing.allocator;
    const input = "puts 'hello'   ";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(result.changed);
    try std.testing.expectEqualStrings("puts 'hello'", result.buffer);
}

test "trailing whitespace keeps clean input unchanged" {
    const allocator = std.testing.allocator;
    const input = "foo\nbar\n";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(!result.changed);
    try std.testing.expectEqualStrings(input, result.buffer);
}
