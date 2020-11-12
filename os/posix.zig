const std = @import("std");

const math = std.math;
const builtin = std.builtin;

usingnamespace std.os;

pub const LINGER = extern struct {
    l_onoff: c_int, // Whether or not a socket should remain open to send queued dataa after closesocket() is called.
    l_linger: c_int, // Number of seconds on how long a socket should remain open after closesocket() is called.
};

const funcs = struct {
    pub extern "c" fn shutdown(sock: socket_t, how: c_int) c_int;
};

pub fn shutdown(sock: socket_t, how: c_int) !void {
    const rc = if (builtin.link_libc) funcs.shutdown(sock, how) else system.shutdown(sock, @intCast(i32, how));
    return switch (errno(rc)) {
        0 => {},
        EBADF => error.BadFileDescriptor,
        EINVAL => error.BadArgument,
        ENOTCONN => error.SocketNotConnected,
        ENOTSOCK => error.NotASocket,
        else => |err| unexpectedErrno(err),
    };
}

pub fn read_(fd: fd_t, buf: []u8) !usize {
    const max_count = switch (std.Target.current.os.tag) {
        .linux => 0x7ffff000,
        .macos, .ios, .watchos, .tvos => math.maxInt(i32),
        else => math.maxInt(isize),
    };
    const adjusted_len = math.min(max_count, buf.len);

    while (true) {
        const rc = system.read(fd, buf.ptr, adjusted_len);
        switch (errno(rc)) {
            0 => return @intCast(usize, rc),
            EINTR => continue,
            EINVAL => unreachable,
            EFAULT => unreachable,
            EAGAIN => return error.WouldBlock,
            EBADF => return error.NotOpenForReading, // Can be a race condition.
            EIO => return error.InputOutput,
            EISDIR => return error.IsDir,
            ENOBUFS => return error.SystemResources,
            ENOMEM => return error.SystemResources,
            ENOTCONN => return error.SocketNotConnected,
            ECONNRESET => return error.ConnectionResetByPeer,
            ETIMEDOUT => return error.ConnectionTimedOut,
            else => |err| return unexpectedErrno(err),
        }
    }
    return index;
}

pub fn connect_(sock: socket_t, sock_addr: *const sockaddr, len: socklen_t) !void {
    while (true) {
        return switch (errno(system.connect(sock, sock_addr, len))) {
            0 => {},
            EACCES => error.PermissionDenied,
            EPERM => error.PermissionDenied,
            EADDRINUSE => error.AddressInUse,
            EADDRNOTAVAIL => error.AddressNotAvailable,
            EAFNOSUPPORT => error.AddressFamilyNotSupported,
            EAGAIN, EINPROGRESS => error.WouldBlock,
            EALREADY => unreachable, // The socket is nonblocking and a previous connection attempt has not yet been completed.
            EBADF => unreachable, // sockfd is not a valid open file descriptor.
            ECONNREFUSED => error.ConnectionRefused,
            EFAULT => unreachable, // The socket structure address is outside the user's address space.
            EINTR => continue,
            EISCONN => error.AlreadyConnected, // The socket is already connected.
            ENETUNREACH => error.NetworkUnreachable,
            ENOTSOCK => unreachable, // The file descriptor sockfd does not refer to a socket.
            EPROTOTYPE => unreachable, // The socket type does not support the requested communications protocol.
            ETIMEDOUT => error.ConnectionTimedOut,
            ENOENT => error.FileNotFound, // Returned when socket is AF_UNIX and the given path does not exist.
            else => |err| unexpectedErrno(err),
        };
    }
}

pub fn getsockopt(comptime T: type, handle: socket_t, level: c_int, opt: c_int) !T {
    var val: T = undefined;
    var val_len: c_int = @sizeOf(T);

    const rc = system.getsockopt(handle, level, opt, @ptrCast([*]u8, val), &val_len);
    return switch (errno(rc)) {
        0 => val,
        EBADF => error.BadFileDescriptor, // The argument sockfd is not a valid file descriptor.
        EFAULT => error.InvalidParameter, // The address pointed to by optval or optlen is not in a valid part of the process address space.
        ENOPROTOOPT => error.UnsupportedOption, // The option is unknown at the level indicated.
        ENOTSOCK => error.NotASocket, // The file descriptor sockfd does not refer to a socket.
        else => |err| unexpectedErrno(err),
    };
}

pub fn sigprocmask(flags: anytype, noalias set: ?*const sigset_t, noalias oldset: ?*sigset_t) !void {
    const rc = system.sigprocmask(flags, set, oldset);
    return switch (errno(rc)) {
        0 => {},
        EFAULT => error.InvalidParameter,
        EINVAL => error.BadSignalSet,
        else => |err| unexpectedErrno(err),
    };
}
