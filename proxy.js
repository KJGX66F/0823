const http = require("http");
const net = require("net");

const PORT = Number(process.env.PORT || 8000);
const SB_PORT = Number(process.env.SB_PORT || 10000);

let WS_PATH = process.env.WS_PATH || "/vless";

if (!WS_PATH.startsWith("/")) {
  WS_PATH = "/" + WS_PATH;
}


// ============================================================
// 普通 HTTP
// ============================================================

const server = http.createServer((req, res) => {

  const pathname = req.url.split("?")[0];

  if (pathname === "/") {

    res.writeHead(200, {
      "Content-Type": "text/plain; charset=utf-8",
      "Cache-Control": "no-store"
    });

    res.end("Hostless service is running\n");

    return;
  }


  if (pathname === "/health") {

    res.writeHead(200, {
      "Content-Type": "application/json",
      "Cache-Control": "no-store"
    });

    res.end(JSON.stringify({
      status: "ok"
    }));

    return;
  }


  res.writeHead(404, {
    "Content-Type": "text/plain"
  });

  res.end("Not Found\n");
});


// ============================================================
// WebSocket Upgrade
//
// Hostless
//     ↓
// Node :$PORT
//     ↓
// sing-box :10000
// ============================================================

server.on("upgrade", (req, socket, head) => {

  let pathname;

  try {

    pathname = new URL(
      req.url,
      "http://localhost"
    ).pathname;

  } catch {

    socket.destroy();

    return;
  }


  if (pathname !== WS_PATH) {

    socket.write(
      "HTTP/1.1 404 Not Found\r\n" +
      "Connection: close\r\n" +
      "Content-Length: 0\r\n" +
      "\r\n"
    );

    socket.destroy();

    return;
  }


  const upstream = net.connect(
    {
      host: "127.0.0.1",
      port: SB_PORT
    },
    () => {

      // ======================================================
      // 重建原始 WebSocket HTTP Upgrade 请求
      // ======================================================

      const requestLines = [];

      requestLines.push(
        `${req.method} ${req.url} HTTP/${req.httpVersion}`
      );


      for (
        let i = 0;
        i < req.rawHeaders.length;
        i += 2
      ) {

        requestLines.push(
          `${req.rawHeaders[i]}: ${req.rawHeaders[i + 1]}`
        );
      }


      requestLines.push("");
      requestLines.push("");


      upstream.write(
        requestLines.join("\r\n")
      );


      if (head && head.length) {
        upstream.write(head);
      }


      socket.pipe(upstream);
      upstream.pipe(socket);
    }
  );


  upstream.on("error", (err) => {

    console.error(
      "WebSocket upstream error:",
      err.message
    );


    if (!socket.destroyed) {

      try {

        socket.write(
          "HTTP/1.1 502 Bad Gateway\r\n" +
          "Connection: close\r\n" +
          "Content-Length: 0\r\n" +
          "\r\n"
        );

      } catch {}

      socket.destroy();
    }
  });


  socket.on("error", () => {
    upstream.destroy();
  });


  socket.on("close", () => {
    upstream.destroy();
  });

});


server.on("error", err => {

  console.error(
    "HTTP frontend error:",
    err
  );

  process.exit(1);
});


server.listen(
  PORT,
  "0.0.0.0",
  () => {

    console.log(
      `HTTP frontend listening on 0.0.0.0:${PORT}`
    );

    console.log(
      `Health endpoint: /health`
    );

    console.log(
      `WebSocket path: ${WS_PATH}`
    );

    console.log(
      `WebSocket upstream: 127.0.0.1:${SB_PORT}`
    );
  }
);
