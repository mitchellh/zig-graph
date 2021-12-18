const std = @import("std");
const math = std.math;
const testing = std.testing;
const Allocator = std.mem.Allocator;

/// A list of strongly connected components.
///
/// This is effectively [][]u64 for a DirectedGraph. The u64 value is the
/// hash code, NOT the type T. You should use the lookup function to get the
/// actual vertex.
pub const StronglyConnectedComponents = struct {
    const Self = @This();
    const Entry = std.ArrayList(u64);
    const List = std.ArrayList(Entry);

    /// The list of components. Do not access this directly. This type
    /// also owns all the items, so when deinit is called, all items in this
    /// list will also be deinit-ed.
    list: List,

    /// Iterator is used to iterate through the strongly connected components.
    pub const Iterator = struct {
        list: *const List,
        index: usize = 0,

        /// next returns the list of hash IDs for the vertex. This should be
        /// looked up again with the graph to get the actual vertex value.
        pub fn next(it: *Iterator) ?[]u64 {
            // If we're empty or at the end, we're done.
            if (it.list.items.len == 0 or it.list.items.len <= it.index) return null;

            // Bump the index, return our value
            defer it.index += 1;
            return it.list.items[it.index].items;
        }
    };

    pub fn init(allocator: Allocator) Self {
        return Self{
            .list = List.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.list.items) |v| {
            v.deinit();
        }
        self.list.deinit();
    }

    /// Iterate over all the strongly connected components
    pub fn iterator(self: *const Self) Iterator {
        return .{ .list = &self.list };
    }

    /// The number of distinct strongly connected components.
    pub fn count(self: *const Self) usize {
        return self.list.items.len;
    }
};

/// Calculate the set of strongly connected components in the graph g.
/// The argument g must be a DirectedGraph type.
pub fn stronglyConnectedComponents(
    allocator: Allocator,
    g: anytype,
) StronglyConnectedComponents {
    var acc = sccAcc.init(allocator);
    defer acc.deinit();
    var result = StronglyConnectedComponents.init(allocator);

    var iter = g.values.keyIterator();
    while (iter.next()) |h| {
        if (!acc.map.contains(h.*)) {
            _ = stronglyConnectedStep(allocator, g, &acc, &result, h.*);
        }
    }

    return result;
}

fn stronglyConnectedStep(
    allocator: Allocator,
    g: anytype,
    acc: *sccAcc,
    result: *StronglyConnectedComponents,
    current: u64,
) u32 {
    // TODO(mitchellh): I don't like this unreachable here.
    const idx = acc.visit(current) catch unreachable;
    var minIdx = idx;

    var iter = g.adjOut.getPtr(current).?.keyIterator();
    while (iter.next()) |targetPtr| {
        const target = targetPtr.*;
        const targetIdx = acc.map.get(target) orelse 0;

        if (targetIdx == 0) {
            minIdx = math.min(
                minIdx,
                stronglyConnectedStep(allocator, g, acc, result, target),
            );
        } else if (acc.inStack(target)) {
            minIdx = math.min(minIdx, targetIdx);
        }
    }

    // If this is the vertex we started with then build our result.
    if (idx == minIdx) {
        var scc = std.ArrayList(u64).init(allocator);
        while (true) {
            const v = acc.pop();
            scc.append(v) catch unreachable;
            if (v == current) {
                break;
            }
        }

        result.list.append(scc) catch unreachable;
    }

    return minIdx;
}

/// Internal accumulator used to calculate the strongly connected
/// components. This should not be used publicly.
pub const sccAcc = struct {
    const MapType = std.hash_map.AutoHashMap(u64, Size);
    const StackType = std.ArrayList(u64);

    next: Size,
    map: MapType,
    stack: StackType,

    // Size is the maximum number of vertices that could exist. Our graph
    // is limited to 32 bit numbers due to the underlying usage of HashMap.
    const Size = u32;

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .next = 1,
            .map = MapType.init(allocator),
            .stack = StackType.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.map.deinit();
        self.stack.deinit();
        self.* = undefined;
    }

    pub fn visit(self: *Self, v: u64) !Size {
        const idx = self.next;
        try self.map.put(v, idx);
        self.next += 1;
        try self.stack.append(v);
        return idx;
    }

    pub fn pop(self: *Self) u64 {
        return self.stack.pop();
    }

    pub fn inStack(self: *Self, v: u64) bool {
        for (self.stack.items) |i| {
            if (i == v) {
                return true;
            }
        }

        return false;
    }
};

test "sccAcc" {
    var acc = sccAcc.init(testing.allocator);
    defer acc.deinit();

    // should start at nothing
    try testing.expect(acc.next == 1);
    try testing.expect(!acc.inStack(42));

    // add vertex
    try testing.expect((try acc.visit(42)) == 1);
    try testing.expect(acc.next == 2);
    try testing.expect(acc.inStack(42));

    const v = acc.pop();
    try testing.expect(v == 42);
}

test "StronglyConnectedComponents" {
    var sccs = StronglyConnectedComponents.init(testing.allocator);
    defer sccs.deinit();

    // Initially empty
    try testing.expect(sccs.count() == 0);

    // Build our entries
    var entries = StronglyConnectedComponents.Entry.init(testing.allocator);
    try entries.append(1);
    try entries.append(2);
    try entries.append(3);
    try sccs.list.append(entries);

    // Should have one
    try testing.expect(sccs.count() == 1);

    // Test iteration
    var iter = sccs.iterator();
    var count: u8 = 0;
    while (iter.next()) |set| {
        const expect = [_]u64{ 1, 2, 3 };
        try testing.expectEqual(set.len, 3);
        try testing.expectEqualSlices(u64, set, &expect);
        count += 1;
    }
    try testing.expect(count == 1);
}
