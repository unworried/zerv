const std = @import("std");
const log = std.log.scoped(.server);

const LISTEN_ADDR = "127.0.0.1";
const LISTEN_PORT = 8000;

var listen_fd: std.atomic.Value(std.posix.fd_t) = .init(-1);

pub fn main(init: std.process.Init) !void {
    installSigHandlers();

    log.info("Starting Server", .{});
    try startServer(init.io);
}

fn installSigHandlers() void {
    const act: std.posix.Sigaction = .{
        .handler = .{ .handler = handleSig },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };

    std.posix.sigaction(.INT, &act, null);
    std.posix.sigaction(.TERM, &act, null);
}

fn handleSig(_: std.posix.SIG) callconv(.c) void {
    const fd = listen_fd.load(.acquire);
    if (fd >= 0) {
        _ = std.posix.system.shutdown(fd, std.posix.SHUT.RDWR);
    }
}

fn startServer(io: std.Io) !void {
    log.info("Listening on http://{s}:{d}", .{ LISTEN_ADDR, LISTEN_PORT });
    const addr = comptime std.Io.net.IpAddress.parseIp4(LISTEN_ADDR, LISTEN_PORT) catch @compileError("invalid listen address");

    var serv = try addr.listen(io, .{ .reuse_address = true });
    defer serv.deinit(io);

    listen_fd.store(serv.socket.handle, .release);
    defer listen_fd.store(-1, .release);

    var grp: std.Io.Group = .init;
    defer grp.cancel(io);

    while (true) {
        const stream = serv.accept(io) catch |err| switch (err) {
            error.SocketNotListening => break,
            error.Canceled => break,
            else => return err,
        };
        grp.async(io, handleStream, .{ io, stream });
    }

    log.info("Awaiting connections...", .{});
    try grp.await(io);
    log.info("Stopping server", .{});
}

fn handleStream(io: std.Io, stream: std.Io.net.Stream) !void {
    defer stream.close(io);

    var read_buffer: [4096]u8 = undefined;
    var write_buffer: [4096]u8 = undefined;
    var reader = stream.reader(io, &read_buffer);
    var writer = stream.writer(io, &write_buffer);

    var http_server = std.http.Server.init(&reader.interface, &writer.interface);

    while (true) {
        var req = http_server.receiveHead() catch |err| switch (err) {
            error.HttpConnectionClosing => return,
            error.ReadFailed => {
                log.debug("client read failed: {}", .{reader.err.?});
                return;
            },
            else => {
                log.err("receiveHead failed: {}", .{err});
                return;
            },
        };

        handleReq(&req) catch |err| {
            log.err("failed to respond: {}", .{err});
        };
    }
}

fn handleReq(req: *std.http.Server.Request) !void {
    if (!std.mem.eql(u8, req.head.target, "/"))
        return req.respond("Not Found", .{ .status = .not_found });

    return switch (req.head.method) {
        .GET => req.respond("Hello World!", .{ .status = .ok }),
        else => req.respond("Method Not Allowed", .{ .status = .method_not_allowed }),
    };
}
