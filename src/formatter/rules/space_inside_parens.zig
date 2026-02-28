const std = @import("std");
const rule_types = @import("../rule.zig");
const utils = @import("../utils.zig");

pub const Result = rule_types.RuleResult;

const StringState = enum { none, single, double };

/// Removes spaces immediately inside parentheses on a single line.
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

        if (try utils.handleComment(allocator, source, &builder, &i, &in_comment)) {
            continue;
        }

        if (ch == '\'' or ch == '"') {
            string_state = if (ch == '"') .double else .single;
            try builder.append(allocator, ch);
            i += 1;
            continue;
        }

        if (ch == '(') {
            try builder.append(allocator, '(');
            i += 1;

            const before_skip = i;
            utils.skipSpaces(source, &i);
            if (i >= source.len or source[i] == '\n' or source[i] == '\r') {
                try builder.appendSlice(allocator, source[before_skip..i]);
            }
            continue;
        }

        if (ch == ')') {
            trimTrailingInlineSpaces(&builder);
            try builder.append(allocator, ')');
            i += 1;
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

fn trimTrailingInlineSpaces(builder: *std.ArrayListUnmanaged(u8)) void {
    while (builder.items.len > 0) {
        const ch = builder.items[builder.items.len - 1];
        if (ch == ' ' or ch == '\t') {
            builder.shrinkRetainingCapacity(builder.items.len - 1);
            continue;
        }
        break;
    }
}

test "space inside parens removes spaces around arguments" {
    const allocator = std.testing.allocator;
    const input = "call( a, b )\n";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(result.changed);
    try std.testing.expectEqualStrings("call(a, b)\n", result.buffer);
}

test "space inside parens removes spaces in empty parens" {
    const allocator = std.testing.allocator;
    const input = "call(  )\n";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(result.changed);
    try std.testing.expectEqualStrings("call()\n", result.buffer);
}

test "space inside parens keeps multiline body untouched" {
    const allocator = std.testing.allocator;
    const input = "call(\n  a,\n  b\n)\n";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(!result.changed);
    try std.testing.expectEqualStrings(input, result.buffer);
}

test "space inside parens ignores strings and comments" {
    const allocator = std.testing.allocator;
    const input = "puts \"( a )\"\n# ( a )\ncall( a )\n";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(result.changed);
    try std.testing.expectEqualStrings("puts \"( a )\"\n# ( a )\ncall(a)\n", result.buffer);
}
