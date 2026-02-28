const std = @import("std");
const guard_blank_line = @import("formatter/rules/guard_blank_line.zig");
const empty_lines_around_modifier = @import("formatter/rules/empty_lines_around_modifier.zig");
const operator_spacing = @import("formatter/rules/operator_spacing.zig");
const align_method_chain = @import("formatter/rules/align_method_chain.zig");
const block_brace_spacing = @import("formatter/rules/block_brace_spacing.zig");
const trailing_whitespace = @import("formatter/rules/trailing_whitespace.zig");
const space_after_comma = @import("formatter/rules/space_after_comma.zig");
const space_inside_parens = @import("formatter/rules/space_inside_parens.zig");
const rule_types = @import("formatter/rule.zig");

pub const FormatResult = struct {
    changed: bool,
    buffer: []u8,

    pub fn deinit(self: *FormatResult, allocator: std.mem.Allocator) void {
        if (self.changed) allocator.free(self.buffer);
    }
};

const rules = [_]rule_types.Rule{
    .{ .apply = trailing_whitespace.apply },
    .{ .apply = align_method_chain.apply },
    .{ .apply = guard_blank_line.apply },
    .{ .apply = empty_lines_around_modifier.apply },
    .{ .apply = operator_spacing.apply },
    .{ .apply = space_after_comma.apply },
    .{ .apply = space_inside_parens.apply },
    .{ .apply = block_brace_spacing.apply },
};

fn applyRule(allocator: std.mem.Allocator, current: *FormatResult, rule: rule_types.Rule) !void {
    var result = try rule.apply(allocator, current.buffer);
    if (result.changed) {
        if (current.changed) allocator.free(current.buffer);
        current.* = FormatResult{ .changed = true, .buffer = result.buffer };
    } else {
        result.deinit(allocator);
    }
}

/// Applies all formatting rules to the provided source.
pub fn applyRules(allocator: std.mem.Allocator, source: []const u8) !FormatResult {
    var current = FormatResult{ .changed = false, .buffer = @constCast(source) };
    for (rules) |rule| {
        try applyRule(allocator, &current, rule);
    }

    return current;
}

/// Applies formatting rules and, when changes are detected, updates the file on disk.
/// Returns `true` if the file was modified.
pub fn applyRulesToFile(allocator: std.mem.Allocator, file_path: []const u8, source: []const u8) !bool {
    var result = try applyRules(allocator, source);
    defer result.deinit(allocator);

    if (!result.changed) return false;

    var file = try std.fs.createFileAbsolute(file_path, .{ .truncate = true });
    defer file.close();

    try file.writeAll(result.buffer);
    return true;
}

test "applyRulesToFile writes updates into the file" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.writeFile(.{ .sub_path = "guard.rb", .data = "return if foo\nputs 'bar'\n" });

    const file_path = try tmp_dir.dir.realpathAlloc(allocator, "guard.rb");
    defer allocator.free(file_path);

    const original = try tmp_dir.dir.readFileAlloc(allocator, "guard.rb", std.math.maxInt(usize));
    defer allocator.free(original);

    const changed = try applyRulesToFile(allocator, file_path, original);
    try std.testing.expect(changed);

    const updated = try tmp_dir.dir.readFileAlloc(allocator, "guard.rb", std.math.maxInt(usize));
    defer allocator.free(updated);

    try std.testing.expectEqualStrings("return if foo\n\nputs 'bar'\n", updated);
}
