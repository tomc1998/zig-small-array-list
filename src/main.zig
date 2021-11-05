const std = @import("std");
const testing = std.testing;
const SmallArrayList = @import("lib.zig").SmallArrayList;

export fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "Creating small array list doesn't allocate if less items than size are pushed" {
    var allocator = std.heap.c_allocator;
    var al4 = SmallArrayList(i32, 4).init(allocator);
    try std.testing.expect(al4.is_small());
    _ = try al4.addOne();
    _ = try al4.addOne();
    _ = try al4.addOne();
    _ = try al4.addOne();
    try std.testing.expect(al4.is_small());
}

test "Small array list allocates on overflow" {
    var allocator = std.heap.c_allocator;
    var al4 = SmallArrayList(i32, 4).init(allocator);
    try std.testing.expectEqual(al4.is_small(), true);
    _ = try al4.addOne();
    _ = try al4.addOne();
    _ = try al4.addOne();
    _ = try al4.addOne();
    _ = try al4.addOne();
    try std.testing.expectEqual(al4.is_big(), true);
}

test "std.ArrayList.init" {
    var bytes: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(bytes[0..]).allocator;

    var list = SmallArrayList(i32, 4).init(allocator);
    defer list.deinit();

    try std.testing.expect(list.count() == 0);
}

test "std.ArrayList.basic" {
    var bytes: [1024]u8 = undefined;
    const allocator = &std.heap.FixedBufferAllocator.init(bytes[0..]).allocator;

    var list = SmallArrayList(i32, 4).init(allocator);
    defer list.deinit();

    // setting on empty list is out of bounds
    try std.testing.expectError(error.OutOfBounds, list.setOrError(0, 1));

    {
        var i: usize = 0;
        while (i < 10) : (i += 1) {
            list.append(@intCast(i32, i + 1)) catch unreachable;
        }
    }

    {
        var i: usize = 0;
        while (i < 10) : (i += 1) {
            try std.testing.expect(list.toSlice()[i] == @intCast(i32, i + 1));
        }
    }

    for (list.toSlice()) |v, i| {
        try std.testing.expect(v == @intCast(i32, i + 1));
    }

    for (list.toSliceConst()) |v, i| {
        try std.testing.expect(v == @intCast(i32, i + 1));
    }

    try std.testing.expect(list.pop() == 10);
    try std.testing.expect(list.len == 9);

    list.appendSlice(&[_]i32{
        1,
        2,
        3,
    }) catch unreachable;
    try std.testing.expect(list.len == 12);
    try std.testing.expect(list.pop() == 3);
    try std.testing.expect(list.pop() == 2);
    try std.testing.expect(list.pop() == 1);
    try std.testing.expect(list.len == 9);

    list.appendSlice(&[_]i32{}) catch unreachable;
    try std.testing.expect(list.len == 9);

    // can only set on indices < self.len
    list.set(7, 33);
    list.set(8, 42);

    try std.testing.expectError(error.OutOfBounds, list.setOrError(9, 99));
    try std.testing.expectError(error.OutOfBounds, list.setOrError(10, 123));
    try std.testing.expect(list.pop() == 42);
    try std.testing.expect(list.pop() == 33);
}

test "std.ArrayList.orderedRemove" {
    var list = SmallArrayList(i32, 4).init(std.heap.c_allocator);
    defer list.deinit();

    try list.append(1);
    try list.append(2);
    try list.append(3);
    try list.append(4);
    try list.append(5);
    try list.append(6);
    try list.append(7);

    //remove from middle
    try std.testing.expectEqual(@as(i32, 4), list.orderedRemove(3));
    try std.testing.expectEqual(@as(i32, 5), list.at(3));
    try std.testing.expectEqual(@as(usize, 6), list.len);

    //remove from end
    try std.testing.expectEqual(@as(i32, 7), list.orderedRemove(5));
    try std.testing.expectEqual(@as(usize, 5), list.len);

    //remove from front
    try std.testing.expectEqual(@as(i32, 1), list.orderedRemove(0));
    try std.testing.expectEqual(@as(i32, 2), list.at(0));
    try std.testing.expectEqual(@as(usize, 4), list.len);
}

test "std.ArrayList.swapRemove" {
    var list = SmallArrayList(i32, 4).init(std.heap.c_allocator);
    defer list.deinit();

    try list.append(1);
    try list.append(2);
    try list.append(3);
    try list.append(4);
    try list.append(5);
    try list.append(6);
    try list.append(7);

    //remove from middle
    try std.testing.expect(list.swapRemove(3) == 4);
    try std.testing.expect(list.at(3) == 7);
    try std.testing.expect(list.len == 6);

    //remove from end
    try std.testing.expect(list.swapRemove(5) == 6);
    try std.testing.expect(list.len == 5);

    //remove from front
    try std.testing.expect(list.swapRemove(0) == 1);
    try std.testing.expect(list.at(0) == 5);
    try std.testing.expect(list.len == 4);
}

test "std.ArrayList.swapRemoveOrError" {
    var list = SmallArrayList(i32, 4).init(std.heap.c_allocator);
    defer list.deinit();

    // Test just after initialization
    try std.testing.expectError(error.OutOfBounds, list.swapRemoveOrError(0));

    // Test after adding one item and remote it
    try list.append(1);
    try std.testing.expect((try list.swapRemoveOrError(0)) == 1);
    try std.testing.expectError(error.OutOfBounds, list.swapRemoveOrError(0));

    // Test after adding two items and remote both
    try list.append(1);
    try list.append(2);
    try std.testing.expect((try list.swapRemoveOrError(1)) == 2);
    try std.testing.expect((try list.swapRemoveOrError(0)) == 1);
    try std.testing.expectError(error.OutOfBounds, list.swapRemoveOrError(0));

    // Test out of bounds with one item
    try list.append(1);
    try std.testing.expectError(error.OutOfBounds, list.swapRemoveOrError(1));

    // Test out of bounds with two items
    try list.append(2);
    try std.testing.expectError(error.OutOfBounds, list.swapRemoveOrError(2));
}

test "std.ArrayList.iterator" {
    var list = SmallArrayList(i32, 4).init(std.heap.c_allocator);
    defer list.deinit();

    try list.append(1);
    try list.append(2);
    try list.append(3);

    var count: i32 = 0;
    var it = list.iterator();
    while (it.next()) |next| {
        try std.testing.expect(next == count + 1);
        count += 1;
    }

    try std.testing.expect(count == 3);
    try std.testing.expect(it.next() == null);
    it.reset();
    count = 0;
    while (it.next()) |next| {
        try std.testing.expect(next == count + 1);
        count += 1;
        if (count == 2) break;
    }

    it.reset();
    try std.testing.expect(it.next().? == 1);
}

test "std.ArrayList.insert" {
    var list = SmallArrayList(i32, 4).init(std.heap.c_allocator);
    defer list.deinit();

    try list.append(1);
    try list.append(2);
    try list.append(3);
    try list.insert(0, 5);
    try std.testing.expect(list.toSlice()[0] == 5);
    try std.testing.expect(list.toSlice()[1] == 1);
    try std.testing.expect(list.toSlice()[2] == 2);
    try std.testing.expect(list.toSlice()[3] == 3);
}

test "std.ArrayList.insertSlice" {
    var list = SmallArrayList(i32, 4).init(std.heap.c_allocator);
    defer list.deinit();

    try list.append(1);
    try list.append(2);
    try list.append(3);
    try list.append(4);
    try list.insertSlice(1, &[_]i32{
        9,
        8,
    });
    try std.testing.expect(list.toSlice()[0] == 1);
    try std.testing.expect(list.toSlice()[1] == 9);
    try std.testing.expect(list.toSlice()[2] == 8);
    try std.testing.expect(list.toSlice()[3] == 2);
    try std.testing.expect(list.toSlice()[4] == 3);
    try std.testing.expect(list.toSlice()[5] == 4);

    const items = [_]i32{1};
    try list.insertSlice(0, items[0..0]);
    try std.testing.expect(list.len == 6);
    try std.testing.expect(list.toSlice()[0] == 1);
}
