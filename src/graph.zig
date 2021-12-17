const std = @import("std");
const debug = std.debug;
const assert = debug.assert;
const hash_map = std.hash_map;
const testing = std.testing;
const Allocator = std.mem.Allocator;

/// A directed graph that contains nodes of a given type.
///
/// The Context is the same as the Context for std.hash_map and must
/// provide for a hash function and equality function. This is used to
/// determine graph node equality.
pub fn DirectedGraph(
    comptime T: type,
    comptime Context: type,
) type {
    // This verifies the context has the correct functions (hash and eql)
    comptime hash_map.verifyContext(Context, T, T, u64);

    // The adjacency list type is used to map all edges in the graph.
    // The key is the source node. The value is a map where the key is
    // target node and the value is the edge weight.
    const AdjMapValue = hash_map.AutoHashMap(u64, u64);
    const AdjMap = hash_map.AutoHashMap(u64, AdjMapValue);

    // ValueMap maps hash codes to the actual value.
    const ValueMap = hash_map.AutoHashMap(u64, T);

    return struct {
        // allocator to use for all operations
        allocator: Allocator,

        // ctx is the context implementation
        ctx: Context,

        // adjacency lists for outbound and inbound edges and a map to
        // get the real value.
        adjOut: AdjMap,
        adjIn: AdjMap,
        values: ValueMap,

        const Self = @This();

        /// Size is the maximum size (as a type) that the graph can hold.
        /// This is currently dictated by our usage of HashMap underneath.
        const Size = AdjMap.Size;

        /// initialize a new directed graph. This is used if the Context type
        /// has no data (zero-sized).
        pub fn init(allocator: Allocator) Self {
            if (@sizeOf(Context) != 0) {
                @compileError("Context is non-zero sized. Use initContext instead.");
            }

            return Self{
                .allocator = allocator,
                .ctx = undefined,
                .adjOut = AdjMap.init(allocator),
                .adjIn = AdjMap.init(allocator),
                .values = ValueMap.init(allocator),
            };
        }

        /// deinitialize all the memory associated with the graph. If you
        /// deinitialize the allocator used with this graph you don't need to
        /// call this.
        pub fn deinit(self: *Self) void {
            // Free values for our adj maps
            var it = self.adjOut.iterator();
            while (it.next()) |kv| {
                kv.value_ptr.deinit();
            }
            it = self.adjIn.iterator();
            while (it.next()) |kv| {
                kv.value_ptr.deinit();
            }

            self.adjOut.deinit();
            self.adjIn.deinit();
            self.values.deinit();
            self.* = undefined;
        }

        /// Add a node to the graph.
        pub fn add(self: *Self, v: T) !void {
            const h = self.ctx.hash(v);

            // If we already have this node, then do nothing.
            if (self.adjOut.contains(h)) {
                return;
            }

            try self.adjOut.put(h, AdjMapValue.init(self.allocator));
            try self.adjIn.put(h, AdjMapValue.init(self.allocator));
            try self.values.put(h, v);
        }

        /// Remove a node and all edges to and from the node.
        pub fn remove(self: *Self, v: T) !void {
            const h = self.ctx.hash(v);

            // Forget this value
            _ = self.values.remove(h);

            // Delete in-edges for this vertex.
            if (self.adjOut.getPtr(h)) |map| {
                var it = map.iterator();
                while (it.next()) |kv| {
                    if (self.adjIn.getPtr(kv.key_ptr.*)) |inMap| {
                        _ = inMap.remove(h);
                    }
                }

                map.deinit();
                _ = self.adjOut.remove(h);
            }

            // Delete out-edges for this vertex
            if (self.adjIn.getPtr(h)) |map| {
                var it = map.iterator();
                while (it.next()) |kv| {
                    if (self.adjOut.getPtr(kv.key_ptr.*)) |inMap| {
                        _ = inMap.remove(h);
                    }
                }

                map.deinit();
                _ = self.adjIn.remove(h);
            }
        }

        /// add an edge from one node to another
        pub fn addEdge(self: *Self, from: T, to: T, weight: u64) !void {
            const h1 = self.ctx.hash(from);
            const h2 = self.ctx.hash(to);

            if (self.adjOut.getPtr(h1)) |map| {
                try map.put(h2, weight);
            } else unreachable;

            if (self.adjIn.getPtr(h2)) |map| {
                try map.put(h1, weight);
            } else unreachable;
        }

        /// remove an edge
        pub fn removeEdge(self: *Self, from: T, to: T) !void {
            const h1 = self.ctx.hash(from);
            const h2 = self.ctx.hash(to);

            if (self.adjOut.getPtr(h1)) |map| {
                _ = map.remove(h2);
            } else unreachable;

            if (self.adjIn.getPtr(h2)) |map| {
                _ = map.remove(h1);
            } else unreachable;
        }

        /// getEdge gets the edge from one node to another and returns the
        /// weight, if it exists.
        pub fn getEdge(self: *const Self, from: T, to: T) ?u64 {
            const h1 = self.ctx.hash(from);
            const h2 = self.ctx.hash(to);

            if (self.adjOut.getPtr(h1)) |map| {
                return map.get(h2);
            } else unreachable;
        }

        // reverse reverses the graph. This does NOT make any copies, so
        // any changes to the original affect the reverse and vice versa.
        // Likewise, only one of these graphs should be deinitialized.
        pub fn reverse(self: *const Self) Self {
            return Self{
                .allocator = self.allocator,
                .ctx = self.ctx,
                .adjOut = self.adjIn,
                .adjIn = self.adjOut,
                .values = self.values,
            };
        }

        /// The number of vertices in the graph.
        pub fn countVertices(self: *const Self) Size {
            return self.values.count();
        }

        /// The number of edges in the graph.
        ///
        /// O(V) where V is the # of vertices. We could cache this if we
        /// wanted but its not a very common operation.
        pub fn countEdges(self: *const Self) Size {
            var count: Size = 0;
            var it = self.adjOut.iterator();
            while (it.next()) |kv| {
                count += kv.value_ptr.count();
            }

            return count;
        }
    };
}

test "add and remove vertex" {
    const gtype = DirectedGraph([]const u8, std.hash_map.StringContext);
    var g = gtype.init(testing.allocator);
    defer g.deinit();

    // Add some nodes
    try g.add("A");
    try g.add("A");
    try g.add("B");
    try testing.expect(g.countVertices() == 2);
    try testing.expect(g.countEdges() == 0);

    // add an edge
    try g.addEdge("A", "B", 1);
    try testing.expect(g.countEdges() == 1);

    // Remove a node
    try g.remove("A");
    try testing.expect(g.countVertices() == 1);

    // important: removing a node should remove the edge
    try testing.expect(g.countEdges() == 0);
}

test "add and remove edge" {
    const gtype = DirectedGraph([]const u8, std.hash_map.StringContext);
    var g = gtype.init(testing.allocator);
    defer g.deinit();

    // Add some nodes
    try g.add("A");
    try g.add("A");
    try g.add("B");

    // add an edge
    try g.addEdge("A", "B", 1);
    try g.addEdge("A", "B", 4);
    try testing.expect(g.countEdges() == 1);
    try testing.expect(g.getEdge("A", "B").? == 4);

    // Remove the node
    try g.removeEdge("A", "B");
    try g.removeEdge("A", "B");
    try testing.expect(g.countEdges() == 0);
    try testing.expect(g.countVertices() == 2);
}

test "reverse" {
    const gtype = DirectedGraph([]const u8, std.hash_map.StringContext);
    var g = gtype.init(testing.allocator);
    defer g.deinit();

    // Add some nodes
    try g.add("A");
    try g.add("B");
    try g.addEdge("A", "B", 1);

    // Reverse
    const rev = g.reverse();

    // Should have the same number
    try testing.expect(rev.countEdges() == 1);
    try testing.expect(rev.countVertices() == 2);
    try testing.expect(rev.getEdge("A", "B") == null);
    try testing.expect(rev.getEdge("B", "A").? == 1);
}
