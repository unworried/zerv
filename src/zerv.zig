const std = @import("std");
const log = std.log.scoped(.zerv);

pub const HandlerError = anyerror;
pub const Handler = *const fn (*std.http.Server.Request) HandlerError!void;

pub const Route = struct {
    method: std.http.Method,
    path: []const u8,
    handler: Handler,
};

pub const Server = struct {
    shutting_down: std.atomic.Value(bool) = .init(false),
    listen_fd: std.atomic.Value(std.posix.fd_t) = .init(-1),

    routes: []const Route,

    pub fn init(routes: []const Route) Server {
        return .{ .routes = routes };
    }

    pub fn shutdown(self: *Server) void {
        self.shutting_down.store(true, .monotonic);
        const fd = self.listen_fd.load(.monotonic);
        if (fd >= 0) {
            _ = std.posix.system.shutdown(fd, std.posix.SHUT.RDWR);
        }
    }

    pub fn listen(self: *Server, io: std.Io, addr: []const u8, port: u16) !void {
        const paddr = try std.Io.net.IpAddress.parseIp4(addr, port);

        var serv = try paddr.listen(io, .{ .reuse_address = true });
        defer serv.deinit(io);

        log.info("Listening on http://{s}:{d}", .{ addr, port });

        self.listen_fd.store(serv.socket.handle, .monotonic);
        defer self.listen_fd.store(-1, .monotonic);

        var grp: std.Io.Group = .init;
        defer grp.cancel(io);

        while (true) {
            const stream = serv.accept(io) catch |err| switch (err) {
                error.SocketNotListening, error.Canceled => break,
                else => return err,
            };
            grp.async(io, handleStream, .{ self, io, stream });
        }

        log.info("Awaiting connections...", .{});
        try grp.await(io);
    }

    fn handleStream(self: *Server, io: std.Io, stream: std.Io.net.Stream) void {
        defer stream.close(io);

        var read_buffer: [4096]u8 = undefined;
        var write_buffer: [4096]u8 = undefined;
        var reader = stream.reader(io, &read_buffer);
        var writer = stream.writer(io, &write_buffer);

        var http_server = std.http.Server.init(&reader.interface, &writer.interface);

        while (!self.shutting_down.load(.monotonic)) {
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

            self.handleReq(&req) catch |err| {
                log.err("req handler failed: {}", .{err});
                req.respond("Internal Server Error", .{ .status = .internal_server_error }) catch {};
                return;
            };
        }
    }

    fn handleReq(self: *Server, req: *std.http.Server.Request) !void {
        for (self.routes) |route| {
            const path = std.mem.sliceTo(req.head.target, '?');
            if (route.method == req.head.method and std.mem.eql(u8, route.path, path)) {
                return route.handler(req);
            }
        }

        return req.respond("Not Found", .{ .status = .not_found });
    }
};
