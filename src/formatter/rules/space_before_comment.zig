const std = @import("std");
const rule_types = @import("../rule.zig");

pub const Result = rule_types.RuleResult;

const StringState = enum { none, single, double };

/// Ensures inline comments are preceded by two spaces.
pub fn apply(allocator: std.mem.Allocator, source: []const u8) !Result {
    var builder = std.ArrayListUnmanaged(u8){};
    errdefer builder.deinit(allocator);

    var i: usize = 0;
    var string_state = StringState.none;
    var escape_in_string = false;
    var line_has_code = false;

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

        if (ch == '\'' or ch == '"') {
            string_state = if (ch == '"') .double else .single;
            try builder.append(allocator, ch);
            line_has_code = true;
            i += 1;
            continue;
        }

        if (ch == '#') {
            if (line_has_code) {
                ensureTwoSpacesBeforeComment(allocator, &builder) catch |err| return err;
            }
            try builder.append(allocator, '#');
            i += 1;
            while (i < source.len and source[i] != '\n') : (i += 1) {
                try builder.append(allocator, source[i]);
            }
            continue;
        }

        try builder.append(allocator, ch);
        if (ch == '\n') {
            line_has_code = false;
        } else if (ch != ' ' and ch != '\t' and ch != '\r') {
            line_has_code = true;
        }
        i += 1;
    }

    if (builder.items.len == source.len and std.mem.eql(u8, builder.items, source)) {
        builder.deinit(allocator);
        return Result{ .changed = false, .buffer = @constCast(source) };
    }

    return Result{ .changed = true, .buffer = try builder.toOwnedSlice(allocator) };
}

fn ensureTwoSpacesBeforeComment(allocator: std.mem.Allocator, builder: *std.ArrayListUnmanaged(u8)) !void {
    var trailing: usize = 0;
    while (trailing < builder.items.len) : (trailing += 1) {
        const ch = builder.items[builder.items.len - 1 - trailing];
        if (ch != ' ' and ch != '\t') break;
    }

    const keep_len = builder.items.len - trailing;
    if (keep_len == 0 or builder.items[keep_len - 1] == '\n') return;

    builder.shrinkRetainingCapacity(keep_len);
    try builder.appendSlice(allocator, "  ");
}

test "space before comment inserts two spaces before inline comment" {
    const allocator = std.testing.allocator;
    const input = "value = 1 # comment\n";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(result.changed);
    try std.testing.expectEqualStrings("value = 1  # comment\n", result.buffer);
}

test "space before comment normalizes excess spaces before comment" {
    const allocator = std.testing.allocator;
    const input = "value = 1     # comment\n";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(result.changed);
    try std.testing.expectEqualStrings("value = 1  # comment\n", result.buffer);
}

test "space before comment keeps standalone comment line unchanged" {
    const allocator = std.testing.allocator;
    const input = "# comment\nvalue = 1\n";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(!result.changed);
    try std.testing.expectEqualStrings(input, result.buffer);
}

test "space before comment ignores hash inside string" {
    const allocator = std.testing.allocator;
    const input = "puts \"# comment\"\nvalue = 1 # note\n";
    var result = try apply(allocator, input);
    defer result.deinit(allocator);

    try std.testing.expect(result.changed);
    try std.testing.expectEqualStrings("puts \"# comment\"\nvalue = 1  # note\n", result.buffer);
}
