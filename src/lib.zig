const Allocator = std.mem.Allocator;
const std = @import("std");

pub fn SmallArrayList(comptime T: type, comptime size: usize) type {
    return AlignedSmallArrayList(T, size, null);
}

/// An array list with a small size optimisation. length is shrunk to u32, to
/// take advantage of this, rather than a usize (since the use case for this
/// will probably be many arrays which barely stores any elements).
pub fn AlignedSmallArrayList(
    comptime T: type,
    comptime size: usize,
    comptime alignment: ?u29,
) type {
    const Slice = if (alignment) |a| ([]align(a) T) else []T;
    const SliceConst = if (alignment) |a| ([]align(a) const T) else []const T;

    const ArrayListItems = union(enum) {
        /// Use toSlice instead of slicing this directly, because if you don't
        /// specify the end position of the slice, this will potentially give
        /// you uninitialized std.memory.
        Big: Slice,
        /// In the small case, this is just an array.
        Small: [size]T,
    };

    const ArrayListItemsTagType = std.meta.Tag(ArrayListItems);

    return struct {
        pub const Self = @This();
        pub const Slice = Slice;
        pub const SliceConst = Slice;

        /// Either small storage (local, inline with struct) or big (heap allocated) storage
        items: ArrayListItems,
        len: u32,

        pub fn init() Self {
            return Self{
                .items = ArrayListItems{ .Small = undefined },
                .len = 0,
            };
        }

        pub fn deinit(self: *const Self, allocator: *Allocator) void {
            if (self.is_small()) {
                return;
            }
            allocator.free(self.items.Big);
        }

        pub fn at(self: *const Self, i: usize) T {
            return self.toSliceConst()[i];
        }

        /// Sets the value at index `i`, or returns `error.OutOfBounds` if
        /// the index is not in range.
        pub fn setOrError(self: *Self, i: usize, item: T) !void {
            if (i >= self.len) return error.OutOfBounds;
            self.itemsAsSlice()[i] = item;
        }

        pub fn toSlice(self: *Self) Slice {
            return self.itemsAsSlice()[0..self.len];
        }

        pub fn toSliceConst(self: *const Self) SliceConst {
            return self.itemsAsSliceConst()[0..self.len];
        }

        pub fn orderedRemove(self: *Self, i: usize) T {
            const newlen = self.len - 1;
            if (newlen == i) return self.pop();

            const old_item = self.at(i);
            for (self.itemsAsSlice()[i..newlen]) |*b, j| b.* = self.itemsAsSlice()[i + 1 + j];
            self.itemsAsSlice()[newlen] = undefined;
            self.len = newlen;
            return old_item;
        }

        /// Removes the element at the specified index and returns it.
        /// The empty slot is filled from the end of the list.
        pub fn swapRemove(self: *Self, i: usize) T {
            if (self.len - 1 == i) return self.pop();

            const slice = self.toSlice();
            const old_item = slice[i];
            slice[i] = self.pop();
            return old_item;
        }

        /// Removes the element at the specified index and returns it
        /// or an error.OutOfBounds is returned. If no error then
        /// the empty slot is filled from the end of the list.
        pub fn swapRemoveOrError(self: *Self, i: usize) !T {
            if (i >= self.len) return error.OutOfBounds;
            return self.swapRemove(i);
        }

        pub fn appendSlice(self: *Self, allocator: *Allocator, items: SliceConst) !void {
            try self.ensureCapacity(allocator, self.len + items.len);
            std.mem.copy(T, self.itemsAsSlice()[self.len..], items);
            self.len += @intCast(u32, items.len);
        }

        pub fn resize(self: *Self, allocator: *Allocator, new_len: usize) !void {
            try self.ensureCapacity(allocator, new_len);
            self.len = new_len;
        }

        pub fn shrink(self: *Self, allocator: *Allocator, new_len: usize) void {
            std.debug.assert(new_len <= self.len);
            self.len = new_len;
            var slice = self.itemsAsSlice();
            slice = allocator.realloc(self.itemsAsSlice(), new_len) catch |e| switch (e) {
                error.OutOfMemory => return, // no problem, capacity is still correct then.
            };
        }

        /// ArrayList takes ownership of the passed in slice. The slice must have been
        /// allocated with `allocator`.
        /// Deinitialize with `deinit` or use `toOwnedSlice`.
        pub fn fromOwnedSlice(slice: Slice) Self {
            return Self{
                .items = ArrayListItems{ .Big = slice },
                .len = slice.len,
            };
        }

        /// The caller owns the returned std.memory. ArrayList becomes empty.
        pub fn toOwnedSlice(self: *Self, allocator: *Allocator) Slice {
            const result = allocator.shrink(allocator, self.itemsAsSlice(), self.len);
            self.* = init();
            return result;
        }

        pub fn insert(self: *Self, allocator: *Allocator, n: usize, item: T) !void {
            try self.ensureCapacity(allocator, self.len + 1);
            self.len += 1;

            std.mem.copyBackwards(T, self.itemsAsSlice()[n + 1 .. self.len], self.itemsAsSlice()[n .. self.len - 1]);
            self.itemsAsSlice()[n] = item;
        }

        pub fn insertSlice(self: *Self, allocator: *Allocator, n: usize, items: SliceConst) !void {
            try self.ensureCapacity(allocator, self.len + items.len);
            self.len += @intCast(u32, items.len);

            std.mem.copyBackwards(T, self.itemsAsSlice()[n + items.len .. self.len], self.itemsAsSlice()[n .. self.len - items.len]);
            std.mem.copy(T, self.itemsAsSlice()[n .. n + items.len], items);
        }

        pub fn append(self: *Self, allocator: *Allocator, item: T) !void {
            const new_item_ptr = try self.addOne(allocator);
            new_item_ptr.* = item;
        }

        /// Access ALL items as slice regardless of big / small (even undefined elements)
        fn itemsAsSlice(self: *Self) Slice {
            // Need to use if rather than switch, compiler's having issues with
            // const / non-const slicing even though we own `Self`.
            if (std.meta.activeTag(self.items) == ArrayListItemsTagType.Big) {
                return self.items.Big;
            } else {
                return &self.items.Small;
            }
        }
        /// Access ALL items as slice regardless of big / small (even undefined elements)
        fn itemsAsSliceConst(self: *const Self) SliceConst {
            // Need to use if rather than switch, compiler's having issues with
            // const / non-const slicing even though we own `Self`.
            if (std.meta.activeTag(self.items) == ArrayListItemsTagType.Big) {
                return self.items.Big;
            } else {
                return &self.items.Small;
            }
        }

        /// Sets the value at index `i`, asserting that the value is in range.
        pub fn set(self: *Self, i: usize, item: T) void {
            std.debug.assert(i < self.len);
            self.itemsAsSlice()[i] = item;
        }

        pub fn count(self: *const Self) usize {
            return self.len;
        }

        pub fn capacity(self: *const Self) usize {
            return switch (self.items) {
                ArrayListItems.Big => |slice| slice.len,
                ArrayListItems.Small => |_| size,
            };
        }

        pub fn ensureCapacity(self: *Self, allocator: *Allocator, new_capacity: usize) !void {
            var better_capacity = self.capacity();
            if (better_capacity >= new_capacity) return;
            while (true) {
                better_capacity += better_capacity / 2 + 8;
                if (better_capacity >= new_capacity) break;
            }
            self.items = switch (self.items) {
                ArrayListItems.Big => |big| ArrayListItems{ .Big = try allocator.realloc(big, better_capacity) },
                ArrayListItems.Small => |_| v: {
                    var newMem = try allocator.alloc(T, better_capacity);
                    std.mem.copy(T, newMem, self.itemsAsSlice());
                    break :v ArrayListItems{ .Big = newMem };
                },
            };
        }

        pub fn addOne(self: *Self, allocator: *Allocator) !*T {
            const new_length = self.len + 1;
            try self.ensureCapacity(allocator, new_length);
            return self.addOneAssumeCapacity();
        }

        pub fn addOneAssumeCapacity(self: *Self) *T {
            std.debug.assert(self.count() < self.capacity());
            const result = &self.itemsAsSlice()[self.len];
            self.len += 1;
            return result;
        }

        pub fn pop(self: *Self) T {
            self.len -= 1;
            return self.itemsAsSlice()[self.len];
        }

        pub fn popOrNull(self: *Self) ?T {
            if (self.len == 0) return null;
            return self.pop();
        }

        pub fn is_small(self: *const Self) bool {
            return std.meta.activeTag(self.items) == ArrayListItemsTagType.Small;
        }
        pub fn is_big(self: *const Self) bool {
            return !self.is_small();
        }

        pub const Iterator = struct {
            list: *const Self,
            // how many items have we returned
            count: usize,

            pub fn next(it: *Iterator) ?T {
                if (it.count >= it.list.len) return null;
                const val = it.list.at(it.count);
                it.count += 1;
                return val;
            }

            pub fn reset(it: *Iterator) void {
                it.count = 0;
            }
        };

        pub fn iterator(self: *const Self) Iterator {
            return Iterator{
                .list = self,
                .count = 0,
            };
        }
    };
}
