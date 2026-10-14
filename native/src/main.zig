const std = @import("std");
const builtin = @import("builtin");
const compiler = @import("compiler.zig");
const vm = @import("vm.zig");

extern "c" fn open(path: [*:0]const u8, flags: c_int, mode: c_uint) c_int;
extern "c" fn read(fd: c_int, buf: [*]u8, count: usize) isize;
extern "c" fn close(fd: c_int) c_int;

extern "c" fn _open(path: [*:0]const u8, flags: c_int, mode: c_uint) c_int;
extern "c" fn _read(fd: c_int, buf: [*]u8, count: c_uint) c_int;
extern "c" fn _close(fd: c_int) c_int;

fn c_open(path: [*:0]const u8) c_int {
    if (builtin.os.tag == .windows) {
        return _open(path, 0, 0);
    } else {
        return open(path, 0, 0);
    }
}

fn c_read(fd: c_int, buf: [*]u8, count: usize) isize {
    if (builtin.os.tag == .windows) {
        const n = _read(fd, buf, @intCast(count));
        return @intCast(n);
    } else {
        return read(fd, buf, count);
    }
}

fn c_close(fd: c_int) void {
    if (builtin.os.tag == .windows) {
        _ = _close(fd);
    } else {
        _ = close(fd);
    }
}

fn readFile(allocator: std.mem.Allocator, path: []const u8) ?[]const u8 {
    var path_buf: [1024]u8 = undefined;
    if (path.len >= path_buf.len) return null;
    @memcpy(path_buf[0..path.len], path);
    path_buf[path.len] = 0;
    const path_z: [*:0]const u8 = path_buf[0..path.len :0];

    const fd = c_open(path_z);
    if (fd < 0) return null;
    defer c_close(fd);

    var buf = allocator.alloc(u8, 65536) catch return null;
    const n = c_read(fd, buf.ptr, buf.len);
    if (n <= 0) {
        allocator.free(buf);
        return null;
    }
    return buf[0..@intCast(n)];
}

fn printResult(res: vm.Value) void {
    if (res.val_type == .str) {
        std.debug.print("{s}\n", .{res.toSlice()});
    } else {
        if (res.num == @trunc(res.num) and @abs(res.num) < 9007199254740992.0) {
            std.debug.print("{d}\n", .{@as(i64, @intFromFloat(res.num))});
        } else {
            std.debug.print("{d}\n", .{res.num});
        }
    }
}

fn drainDbgOut() void {
    const n = vm.dbgOutLen();
    if (n == 0) return;
    var buf: [256]u8 = undefined;
    const len = vm.dbgTake(buf[0..]);
    if (len > 0) {
        std.debug.print("{s}", .{buf[0..len]});
    }
}

const max_in_retries: usize = 64;

/// Run with Dbg.in support: on InputEmpty, snapshot-restore state, read one
/// stdin line (blocking, CLI only), feed it, and rerun for exact-once semantics.
fn runWithInput(prog: *vm.Prog, entry_ip: usize, allocator: std.mem.Allocator) vm.EvalError!vm.Value {
    const saved_state = allocator.dupe(vm.Value, prog.state_slots) catch null;
    defer if (saved_state) |s| allocator.free(s);
    var in_buf: [256]u8 = undefined;
    var retries: usize = 0;
    while (true) {
        const res = vm.run(prog, entry_ip, &[_]f64{}) catch |err| {
            if (err != error.InputEmpty) return err;
            if (retries >= max_in_retries) return err;
            retries += 1;
            if (saved_state) |s| @memcpy(prog.state_slots, s);
            std.debug.print("in> ", .{});
            const n = c_read(0, in_buf[0..].ptr, in_buf.len);
            if (n <= 0) return err;
            const line = std.mem.trim(u8, in_buf[0..@intCast(n)], "\r\n");
            _ = vm.dbgFeed(line);
            continue;
        };
        return res;
    }
}

pub fn main(init: std.process.Init.Minimal) !void {
    const allocator = std.heap.c_allocator;

    var it = try std.process.Args.Iterator.initAllocator(init.args, allocator);
    defer it.deinit();

    _ = it.next();

    const first_arg = it.next();

    if (first_arg) |arg| {
        var source: []const u8 = arg;
        var file_buffer: ?[]const u8 = null;
        defer if (file_buffer) |buf| allocator.free(buf);

        if (std.mem.eql(u8, arg, "-e")) {
            if (it.next()) |code| {
                source = code;
            }
        } else if (std.mem.endsWith(u8, arg, ".o5s")) {
            if (readFile(allocator, arg)) |content| {
                source = content;
                file_buffer = content;
            }
        }

        const prog = compiler.compileSource(source, allocator) catch |err| {
            std.debug.print("Compile error: {}\n", .{err});
            return;
        };
        defer prog.deinit();

        const res = runWithInput(prog, 0, allocator) catch |err| {
            std.debug.print("Runtime error: {}\n", .{err});
            return;
        };
        drainDbgOut();

        if (prog.tags.len == 0 or res.num != 0.0 or res.val_type == .str) {
            printResult(res);
        }
        if (prog.tags.len > 0) {
            for (prog.tags) |tag_def| {
                const tag_res = runWithInput(prog, tag_def.entry_ip, allocator) catch continue;
                drainDbgOut();
                std.debug.print("[Tag: #{s}] => ", .{tag_def.name});
                printResult(tag_res);
            }
        }
        return;
    }

    std.debug.print("O5Script v0.1.0 (Zero-Cost Native Engine)\n", .{});
    std.debug.print("Type an expression, or 'exit' to quit.\n\n", .{});

    var buf: [4096]u8 = undefined;

    while (true) {
        std.debug.print("o5s> ", .{});
        const n = c_read(0, buf[0..].ptr, buf.len);
        if (n <= 0) break;
        const line = buf[0..@intCast(n)];
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0) continue;
        if (std.mem.eql(u8, trimmed, "exit") or std.mem.eql(u8, trimmed, "quit")) break;

        const prog = compiler.compileSource(trimmed, allocator) catch |err| {
            std.debug.print("Error: {}\n", .{err});
            continue;
        };
        defer prog.deinit();

        const res = runWithInput(prog, 0, allocator) catch |err| {
            std.debug.print("Error: {}\n", .{err});
            continue;
        };
        drainDbgOut();

        printResult(res);
    }
}
