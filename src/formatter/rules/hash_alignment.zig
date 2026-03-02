const std = @import("std");
const rule_types = @import("../rule.zig");

pub const Result = rule_types.RuleResult;

const Entry = struct {
    line_index: usize,
    indent_len: usize,
    colon_index: usize,
    value_start: usize,
    value_end: usize,
    trailing: []const u8,
};

/// Aligns values in consecutive multi-line hash label entries.
pub fn apply(allocator: std.mem.Allocator, source: []const u8) !Result {
    var raw_lines = std.ArrayList([]const u8).init(allocator);
    defer raw_lines.deinit();

    var iter = std.mem.splitScalar(u8, source, '\n');
    while (iter.next()) |line| {
        try raw_lines.append(line);
    }

    var output = std.ArrayList([]u8).init(allocator);
    defer {
        for (output.items) |line| allocator.free(line);
        output.deinit();
    }

    for (raw_lines.items) |line| {
        try output.append(try allocator.dupe(u8, line));
    }

    var changed = false;
    var index: usize = 0;
    while (index < raw_lines.items.len) {
        if (try collectAndAlignGroup(allocator, raw_lines.items, output.items, &index)) {
            changed = true;
        }
    }

    if (!changed) {
        return Result{ .changed = false, .buffer = @constCast(source) };
    }

    var builder = std.ArrayListUnmanaged(u8){};
    errdefer builder.deinit(allocator);
    for (output.items, 0..) |line, i| {
        if (i != 0) try builder.append(allocator, '\n');
        try builder.appendSlice(allocator, line);
    }

    return Result{ .changed = true, .buffer = try builder.toOwnedSlice(allocator) };
}

fn collectAndAlignGroup(
    allocator: std.mem.Allocator,
    raw_lines: []const []const u8,
    output_lines: [][]u8,
    index: *usize,
) !bool {
    const first_base = parseHashEntry(raw_lines[index.*]) orelse {
        index.* += 1;
        return false;
    };
    var first = first_base;
    first.line_index = index.*;

    var entries = std.ArrayList(Entry).init(allocator);
    defer entries.deinit();
    try entries.append(first);

    var max_value_column = first.value_start;
    var scan = index.* + 1;
    while (scan < raw_lines.len) : (scan += 1) {
        const next_base = parseHashEntry(raw_lines[scan]) orelse break;
        var next = next_base;
        next.line_index = scan;
        if (next.indent_len != first.indent_len) break;
        try entries.append(next);
        if (next.value_start > max_value_column) max_value_column = next.value_start;
    }

    index.* = scan;
    if (entries.items.len < 2) return false;

    var changed = false;
    for (entries.items) |entry| {
        const line = raw_lines[entry.line_index];
        const prefix = line[0..entry.colon_index + 1];
        const value = std.mem.trimLeft(u8, line[entry.value_start..entry.value_end], " \t");
        const spaces = max_value_column - entry.colon_index;

        var rebuilt = std.ArrayListUnmanaged(u8){};
        defer rebuilt.deinit(allocator);
        try rebuilt.appendSlice(allocator, prefix);
        var n = spaces;
        while (n > 0) : (n -= 1) try rebuilt.append(allocator, ' ');
        try rebuilt.appendSlice(allocator, value);
        try rebuilt.appendSlice(allocator, entry.trailing);

        if (!std.mem.eql(u8, rebuilt.items, output_lines[entry.line_index])) {
            allocator.free(output_lines[entry.line_index]);
            output_lines[entry.line_index] = try rebuilt.toOwnedSlice(allocator);
            changed = true;
        }
    }

    return changed;
}

fn parseHashEntry(line: []const u8) ?Entry {
    const indent_len = line.len - std.mem.trimLeft(u8, line, " \t").len;
    const trimmed = line[indent_len..];
    if (trimmed.len == 0) return null;
    if (trimmed[0] == '#' or trimmed[0] == '}' or trimmed[0] == ']') return null;

    const colon_rel = std.mem.indexOfScalar(u8, trimmed, ':') orelse return null;
    if (colon_rel == 0 or colon_rel + 1 >= trimmed.len) return null;
    if (!isIdentifier(trimmed[0..colon_rel])) return null;

    const colon_index = indent_len + colon_rel;
    var value_start = colon_index + 1;
    while (value_start < line.len and (line[value_start] == ' ' or line[value_start] == '\t')) : (value_start += 1) {}
    if (value_start >= line.len) return null;

    var value_end = line.len;
    var trailing: []const u8 = "";
    if (line.len > 0 and line[line.len - 1] == ',') {
        value_end = line.len - 1;
        trailing = ",";
    }

    return Entry{
        .line_index = 0,
        .indent_len = indent_len,
        .colon_index = colon_index,
        .value_start = value_start,
        .value_end = value_end,
        .trailing = trailing,
    };
}

fn isIdentifier(text: []const u8) bool {
    if (text.len == 0) return false;
    for (text) |ch| {
        if (!std.ascii.isAlphanumeric(ch) and ch != '_') return false;
    }
    return true;
}

test "hash alignment aligns values for consecutive hash entries" {
    const allocator = std.testing.allocator;
    const input =
        \\config = {
        \\  short: 1,
        \\  longer_key: 2,
        \\}
        \\
    ;
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(result.changed);
    try std.testing.expectEqualStrings(
        \\config = {
        \\  short:      1,
        \\  longer_key: 2,
        \\}
        \\
    , result.buffer);
}

test "hash alignment keeps already aligned values unchanged" {
    const allocator = std.testing.allocator;
    const input =
        \\config = {
        \\  short:      1,
        \\  longer_key: 2,
        \\}
        \\
    ;
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(!result.changed);
    try std.testing.expectEqualStrings(input, result.buffer);
}

test "hash alignment ignores single hash entry" {
    const allocator = std.testing.allocator;
    const input = "config = {\n  short: 1,\n}\n";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(!result.changed);
    try std.testing.expectEqualStrings(input, result.buffer);
}
