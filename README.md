# zig-graph

A Zig library for directed graph data structures and associated algorithms.
This library can be used for acyclic and cyclic graphs and unweighted and weighted
edges. This library requires Zig 0.9+.

**Warning: This is literally the first piece of Zig code I've ever written
in my life.** I'm using this project as a way to learn how to do things in
Zig, what is idiomatic, what isn't, etc. Feedback is very welcome on how
I can improve and I expect to alter the library a bit as I do so.  There is
also a lot of room for improvement in performance by various measures.

## Features

* Directed edges
* Cycle detection
* Strongly connected components
* Cheap edge reversal
* Depth-first traversal

#### TODO

* Vertex iterator
* Edge iterator
* Dijkstra for single-source shortest path w/ edge-weighting
* Kahn for topological sorting
* Shortest path given a topological sort
* String marshaling for easier debugging
* "Unmanaged" graph so allocator can be sent to each op

## Example

```zig
const std = @import("std");
const graph = @import("graph");

pub fn main() void {
	// Create a directed graph type for strings.
	const Graph = graph.DirectedGraph([]const u8, std.hash_map.StringContext);

	// Initialize using some allocator
	var g = Graph.init(std.debug.global_allocator);
	defer g.deinit();

	// Add some vertices
	try g.add("A");
	try g.add("B");
	try g.add("C");

	// Add some edges with weights. For unweighted edges just make all
	// weights the same value.
	try g.addEdge("A", "B", 5);
	try g.addEdge("A", "C", 2);
	try g.addEdge("B", "C", 2);
	try g.addEdge("C", "B", 3);

	// We can detect cycles
	if (g.cycles()) |cycles| {
		defer cycles.deinit();
		std.log.info("there are {d} cycles", .{cycles.count()});
		return;
	}

	// We can do a depth-first search through iteration.
	var dfsIter = try g.dfsIterator("B");
	while (dfsIter.next()) |id| {
		std.log.info("{}", .{g.lookup(id).?});
	}
	dfsIter.deinit();

	// We can easily reverse the graph if we want.
	const reversed = g.reverse();

	// ... and more
}
```
