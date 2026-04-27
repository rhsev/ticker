import Foundation

let socketPath = "/tmp/menubar_ticker.sock"

func runSocketServer(onMessage: @escaping (TickerMessage) -> Void) {
    DispatchQueue.global(qos: .background).async {
        unlink(socketPath)

        let serverFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFd >= 0 else { return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { src in
            withUnsafeMutablePointer(to: &addr.sun_path.0) { _ = strcpy($0, src) }
        }

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverFd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else { return }
        listen(serverFd, 8)

        var tv = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(serverFd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        while true {
            var clientAddr = sockaddr_un()
            var len = socklen_t(MemoryLayout<sockaddr_un>.size)
            let clientFd = withUnsafeMutablePointer(to: &clientAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    accept(serverFd, $0, &len)
                }
            }
            guard clientFd >= 0 else { continue }

            var buffer = [UInt8](repeating: 0, count: 4096)
            let n = recv(clientFd, &buffer, buffer.count, 0)
            if n > 0,
               let raw = String(bytes: buffer[0..<n], encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines),
               let msg = decodeSocketMessage(raw)
            {
                onMessage(msg)
                _ = "OK".withCString { send(clientFd, $0, 2, 0) }
            } else {
                _ = "Error".withCString { send(clientFd, $0, 5, 0) }
            }
            close(clientFd)
        }
    }
}

// ── CLI send ───────────────────────────────────────────────────────────────────

func cliSend(_ msg: TickerMessage) {
    guard FileManager.default.fileExists(atPath: socketPath) else {
        fputs("Error: ticker is not running.\n", stderr)
        exit(1)
    }
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    socketPath.withCString { src in
        withUnsafeMutablePointer(to: &addr.sun_path.0) { _ = strcpy($0, src) }
    }
    withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            _ = connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    let payload = encodeSocketMessage(msg)
    payload.withCString { _ = send(fd, $0, strlen($0), 0) }
    var buf = [UInt8](repeating: 0, count: 64)
    let n = recv(fd, &buf, buf.count, 0)
    if n > 0, let resp = String(bytes: buf[0..<n], encoding: .utf8) { print(resp) }
    close(fd)
}
