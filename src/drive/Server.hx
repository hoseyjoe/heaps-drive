package drive;

#if sys
import haxe.io.Bytes;
import drive.Protocol;

/**
 * The automation channel's listener (heaps-drive spec §1): 127.0.0.1 on an OS-chosen port,
 * one client at a time (another is answered `busy` and closed), polled from the UI thread by
 * `tick` with zero-timeout selects, so it never blocks a frame. Client sockets are non-blocking:
 * replies wait in an outbox drained each tick (see SocketConnection), so a client that never reads
 * cannot stall the app.
 */
class Server implements ITransport {
    /** Connections accepted per tick at most (each refused one costs a write and a close). */
    static inline var MAX_ACCEPTS_PER_TICK = 8;

    public var port(default, null):Int;

    var listener:sys.net.Socket;
    var token:String;
    var dispatch:Request->Outcome;
    var clock:Void->Float;
    var session:Null<Session> = null;

    public function new(token:String, dispatch:Request->Outcome, clock:Void->Float) {
        this.token = token;
        this.dispatch = dispatch;
        this.clock = clock;
        listener = new sys.net.Socket();
        listener.bind(new sys.net.Host("127.0.0.1"), 0);
        listener.listen(2);
        port = listener.host().port;
    }

    public function tick():Void {
        // The session first: one that closed since the last tick is let go before a new client is
        // accepted, so a quick reconnect is not answered `busy`.
        if (session != null) {
            session.tick();
            if (session.closed) endSession();
        }
        var accepted = 0;
        while (accepted++ < MAX_ACCEPTS_PER_TICK && sys.net.Socket.select([listener], null, null, 0).read.length > 0) {
            var s = listener.accept();
            if (session != null && !session.closed) refuse(s);
            else {
                endSession();
                session = new Session(new SocketConnection(s), token, dispatch, clock);
                session.onTimeout = () -> onTimeout();
                session.tick();   // answers what already arrived with the connection
                if (session.closed) endSession();
            }
        }
    }

    /** Whether a client is connected. */
    public var connected(get, never):Bool;
    function get_connected():Bool return session != null && !session.closed;

    /** Called whenever a session ends, so the app can let go of input the client left held. */
    public var onClientGone:Void->Void = () -> {};
    /** Called when a deferred request times out, for the same reason. */
    public var onTimeout:Void->Void = () -> {};

    function endSession():Void {
        if (session == null) return;
        var s = session;
        session = null;
        s.close();
        onClientGone();
    }

    function refuse(s:sys.net.Socket):Void {
        try {
            s.setBlocking(false);
            var line = Bytes.ofString(haxe.Json.stringify({id: 0, ok: false, code: "busy", error: "another client is connected"}) + "\n");
            s.output.writeBytes(line, 0, line.length);   // a fresh socket's empty buffer takes it; if not, it is dropped
        } catch (_:Dynamic) {}
        try s.close() catch (_:Dynamic) {}
    }

    /** Stops listening and closes the client's socket. */
    public function close():Void {
        try listener.close() catch (_:Dynamic) {}
        endSession();
    }
}

/**
 * A connected socket as an `IConnection`, non-blocking in both directions.
 * - Reads: at most MAX_READ_PER_TICK bytes a call. Bytes after the last newline are kept until the
 *   rest of their line arrives (so a multi-byte character split across reads decodes whole); more
 *   than MAX_PARTIAL of them, a line with no end in sight, closes the connection.
 * - Writes: `send` appends to an outbox and writes what the socket takes now; the rest goes on each
 *   later `receive` (once a tick). An outbox past MAX_OUTBOX, a client that is not reading, closes
 *   the connection. Nothing here ever waits on the client.
 */
class SocketConnection implements IConnection {
    public static inline var MAX_READ_PER_TICK = 256 * 1024;
    public static inline var MAX_PARTIAL = 1 << 20;
    public static inline var MAX_OUTBOX = 4 << 20;

    var socket:sys.net.Socket;
    var partial:Bytes = Bytes.alloc(0);
    var outbox:Bytes = Bytes.alloc(0);
    var outPos:Int = 0;
    var gone:Bool = false;

    public function new(socket:sys.net.Socket) {
        this.socket = socket;
        socket.setBlocking(false);
    }

    public function receive():Null<String> {
        if (gone) return null;
        drain();
        if (gone) return null;
        var got = new haxe.io.BytesBuffer();
        got.add(partial);
        var read = 0;
        var buf = Bytes.alloc(4096);
        while (read < MAX_READ_PER_TICK && sys.net.Socket.select([socket], null, null, 0).read.length > 0) {
            var n = try socket.input.readBytes(buf, 0, buf.length) catch (e:haxe.io.Error) {
                switch (e) { case Blocked: -1; case _: 0; }
            } catch (_:Dynamic) 0;   // Eof: the client closed
            if (n < 0) break;
            if (n == 0) { gone = true; break; }
            got.addBytes(buf, 0, n);
            read += n;
        }
        var all = got.getBytes();
        var last = -1;
        for (i in 0...all.length) if (all.get(i) == 10) last = i;
        partial = all.sub(last + 1, all.length - last - 1);
        if (partial.length > MAX_PARTIAL) { close(); return null; }
        var text = last < 0 ? "" : all.getString(0, last + 1);
        if (gone && text == "") return null;
        return text;
    }

    public function send(text:String):Void {
        if (gone) throw "the connection is closed";
        var b = Bytes.ofString(text);
        var waiting = outbox.length - outPos;
        if (waiting + b.length > MAX_OUTBOX) { close(); throw "the client is not reading its replies"; }
        var next = Bytes.alloc(waiting + b.length);
        next.blit(0, outbox, outPos, waiting);
        next.blit(waiting, b, 0, b.length);
        outbox = next;
        outPos = 0;
        drain();
        if (gone) throw "the client went away";
    }

    /** Writes as much of the outbox as the socket takes without waiting. */
    function drain():Void {
        while (!gone && outPos < outbox.length) {
            var n = try socket.output.writeBytes(outbox, outPos, outbox.length - outPos) catch (e:haxe.io.Error) {
                switch (e) { case Blocked: 0; case _: -1; }
            } catch (_:Dynamic) -1;   // Eof: the client went away
            if (n < 0) { gone = true; return; }   // receive answers null, and the session closes
            if (n == 0) return;
            outPos += n;
        }
        if (outPos == outbox.length && outPos > 0) { outbox = Bytes.alloc(0); outPos = 0; }
    }

    var socketClosed = false;

    public function close():Void {
        if (socketClosed) return;
        socketClosed = true;
        drain();   // a last reply (`unauthorized`, `bad_request`) goes out if the socket takes it now
        gone = true;
        try socket.close() catch (_:Dynamic) {}
    }
}
#end
