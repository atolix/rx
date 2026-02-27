const std = @import("std");
const rule_types = @import("../rule.zig");
const utils = @import("../utils.zig");

pub const Result = rule_types.RuleResult;

/// Ensures modifier `if/unless` lines are followed by a blank line.
pub fn apply(allocator: std.mem.Allocator, source: []const u8) !Result {
    var lines = std.mem.splitScalar(u8, source, '\n');
    var builder = std.ArrayListUnmanaged(u8){};
    errdefer builder.deinit(allocator);

    var pending_modifier = false;
    var line_index: usize = 0;
    var changed = false;

    while (lines.next()) |line| : (line_index += 1) {
        if (pending_modifier) {
            if (!utils.isBlankLine(line)) {
                try builder.append(allocator, '\n');
                changed = true;
            }
            pending_modifier = false;
        }

        if (line_index != 0) try builder.append(allocator, '\n');
        try builder.appendSlice(allocator, line);

        if (isModifierLine(line)) pending_modifier = true;
    }

    if (pending_modifier) {
        try builder.append(allocator, '\n');
        changed = true;
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

fn isModifierLine(line: []const u8) bool {
    const trimmed = std.mem.trim(u8, line, " \t");
    if (trimmed.len == 0) return false;
    if (trimmed[0] == '#') return false;
    if (std.mem.startsWith(u8, trimmed, "if ") or std.mem.eql(u8, trimmed, "if")) return false;
    if (std.mem.startsWith(u8, trimmed, "unless ") or std.mem.eql(u8, trimmed, "unless")) return false;

    return hasModifierKeyword(trimmed, "if") or hasModifierKeyword(trimmed, "unless");
}

fn hasModifierKeyword(line: []const u8, keyword: []const u8) bool {
    var search_index: usize = 0;

    while (std.mem.indexOfPos(u8, line, search_index, keyword)) |idx| {
        const before = if (idx == 0) null else line[idx - 1];
        const after_index = idx + keyword.len;
        const after = if (after_index < line.len) line[after_index] else null;

        const before_ok = before == null or std.ascii.isWhitespace(before.?);
        const after_ok = after == null or std.ascii.isWhitespace(after.?);
        if (!before_ok or !after_ok) {
            search_index = idx + 1;
            continue;
        }

        const prefix = std.mem.trimRight(u8, line[0..idx], " \t");
        if (prefix.len > 0) return true;

        search_index = idx + 1;
    }

    return false;
}

test "empty lines around modifier inserts blank line after modifier if" {
    const allocator = std.testing.allocator;
    const input = "do_work if ready?\nlog_done\n";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(result.changed);
    try std.testing.expectEqualStrings("do_work if ready?\n\nlog_done\n", result.buffer);
}

test "empty lines around modifier inserts blank line after modifier unless" {
    const allocator = std.testing.allocator;
    const input = "next unless valid?\nhandle\n";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(result.changed);
    try std.testing.expectEqualStrings("next unless valid?\n\nhandle\n", result.buffer);
}

test "empty lines around modifier does not change block if" {
    const allocator = std.testing.allocator;
    const input = "if ready?\n  do_work\nend\n";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(!result.changed);
    try std.testing.expectEqualStrings(input, result.buffer);
}

test "empty lines around modifier keeps existing blank line" {
    const allocator = std.testing.allocator;
    const input = "do_work if ready?\n\nlog_done\n";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(!result.changed);
    try std.testing.expectEqualStrings(input, result.buffer);
}
