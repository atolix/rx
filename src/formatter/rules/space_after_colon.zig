const std = @import("std");
const rule_types = @import("../rule.zig");
const utils = @import("../utils.zig");

pub const Result = rule_types.RuleResult;

const StringState = enum { none, single, double };

/// Ensures hash-style colons are followed by one space on the same line.
pub fn apply(allocator: std.mem.Allocator, source: []const u8) !Result {
    var builder = std.ArrayListUnmanaged(u8){};
    errdefer builder.deinit(allocator);

    var i: usize = 0;
    var string_state = StringState.none;
    var escape_in_string = false;
    var in_comment = false;

    while (i < source.len) {
        const ch = source[i];

        if (string_state != .none) {
            try builder.append(allocator, ch);
            if (escape_in_string) {
                escape_in_string = false;
            } else if (ch == '\\') {
                escape_in_string = true;
            } else if ((string_state == .single and ch == '\'') or (string_state == .double and ch == '"')) {
                string_state = .none;
            }
            i += 1;
            continue;
        }

        if (try utils.handleComment(allocator, source, &builder, &i, &in_comment)) continue;

        if (ch == '\'' or ch == '"') {
            string_state = if (ch == '"') .double else .single;
            try builder.append(allocator, ch);
            i += 1;
            continue;
        }

        if (ch == ':' and isHashColon(source, builder.items, i)) {
            try builder.append(allocator, ':');
            i += 1;

            const start = i;
            utils.skipSpaces(source, &i);
            if (i < source.len and source[i] != '\n' and source[i] != '\r') {
                try builder.append(allocator, ' ');
            } else if (start < i) {
                try builder.appendSlice(allocator, source[start..i]);
            }
            continue;
        }

        try builder.append(allocator, ch);
        i += 1;
    }

    if (builder.items.len == source.len and std.mem.eql(u8, builder.items, source)) {
        builder.deinit(allocator);
        return Result{ .changed = false, .buffer = @constCast(source) };
    }

    return Result{ .changed = true, .buffer = try builder.toOwnedSlice(allocator) };
}

fn isHashColon(source: []const u8, builder_items: []u8, index: usize) bool {
    if (index + 1 < source.len and source[index + 1] == ':') return false;
    if (index == 0) return false;

    const prev = utils.findPrevNonWhitespace(builder_items) orelse return false;
    if (!(std.ascii.isAlphanumeric(prev) or prev == '_' or prev == '"' or prev == '\'')) return false;

    var j = index + 1;
    while (j < source.len and (source[j] == ' ' or source[j] == '\t')) : (j += 1) {}
    if (j >= source.len) return false;
    const next = source[j];
    return next != ':' and next != '\n' and next != '\r';
}

test "space after colon inserts space for hash pairs" {
    const allocator = std.testing.allocator;
    const input = "config = {foo:bar, baz:qux}\n";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(result.changed);
    try std.testing.expectEqualStrings("config = {foo: bar, baz: qux}\n", result.buffer);
}

test "space after colon keeps already spaced hash pairs" {
    const allocator = std.testing.allocator;
    const input = "config = {foo: bar}\n";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(!result.changed);
    try std.testing.expectEqualStrings(input, result.buffer);
}

test "space after colon ignores symbols and double colon" {
    const allocator = std.testing.allocator;
    const input = "puts :symbol\nFoo::Bar\n";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(!result.changed);
    try std.testing.expectEqualStrings(input, result.buffer);
}
