const std = @import("std");
const zerv = @import("zerv");
const log = std.log.scoped(.main);

const LISTEN_ADDR = "127.0.0.1";
const LISTEN_PORT = 8000;

fn index(req: *std.http.Server.Request) !void {
    return req.respond("Hello World!", .{ .status = .ok });
}

const routes = [_]zerv.Route{
    .{ .method = .GET, .path = "/", .handler = index },
};

var g_server: *zerv.Server = undefined;

fn onSignal(_: std.posix.SIG) callconv(.c) void {
    g_server.shutdown();
}

pub fn main(init: std.process.Init) !void {
    log.info("Starting Server", .{});
    var server = zerv.Server.init(&routes);

    g_server = &server;
    const sa = std.posix.Sigaction{
        .handler = .{ .handler = onSignal },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.INT, &sa, null);
    std.posix.sigaction(std.posix.SIG.TERM, &sa, null);

    try server.listen(init.io, LISTEN_ADDR, LISTEN_PORT);
}

fn watchSignals(server: *zerv.Server) void {
    var mask = std.posix.empty_sigset;
    _ = std.c.sigaddset(&mask, std.posix.SIG.INT);
    _ = std.c.sigaddset(&mask, std.posix.SIG.TERM);

    var sig: c_int = undefined;
    _ = std.c.sigwait(&mask, &sig);

    log.info("Received signal {d}, shutting down...", .{sig});
    server.shutdown();
}
