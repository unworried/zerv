const std = @import("std");
const zerv = @import("zerv");
const log = std.log.scoped(.basic);

comptime {
    if (@import("builtin").os.tag != .linux) @compileError("Linux only");
}

const LISTEN_ADDR = "127.0.0.1";
const LISTEN_PORT = 8000;

fn watchShutdown(server: *zerv.Server) void {
    var set = std.posix.sigemptyset();
    std.posix.sigaddset(&set, std.posix.SIG.INT);
    std.posix.sigaddset(&set, std.posix.SIG.TERM);

    const fd = std.posix.signalfd(
        -1,
        &set,
        std.os.linux.SFD.CLOEXEC,
    ) catch |err| {
        log.err("signalfd failed: {}", .{err});
        return;
    };
    defer _ = std.os.linux.close(fd);

    var info: std.os.linux.signalfd_siginfo = undefined;
    _ = std.posix.read(fd, std.mem.asBytes(&info)) catch |err| {
        log.err("signal read failed: {}", .{err});
        return;
    };

    server.shutdown();
}

fn index(req: *std.http.Server.Request) !void {
    return req.respond("Hello World!", .{ .status = .ok });
}

const routes = [_]zerv.Route{
    .{ .method = .GET, .path = "/", .handler = index },
};

pub fn main(init: std.process.Init) !void {
    log.info("Starting Server", .{});
    var server = zerv.Server.init(&routes);

    var set = std.posix.sigemptyset();
    std.posix.sigaddset(&set, std.posix.SIG.INT);
    std.posix.sigaddset(&set, std.posix.SIG.TERM);
    std.posix.sigprocmask(std.posix.SIG.BLOCK, &set, null);

    var shutdown_thread = try std.Thread.spawn(.{}, watchShutdown, .{&server});
    defer shutdown_thread.join();

    try server.listen(init.io, LISTEN_ADDR, LISTEN_PORT);
    log.info("Stopping server", .{});
}
