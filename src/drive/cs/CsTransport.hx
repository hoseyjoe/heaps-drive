package drive.cs;

#if cs
import haxe.io.Bytes;
import drive.Protocol;
import cs.system.net.IPAddress;
import cs.system.net.IPEndPoint;
import cs.system.net.sockets.AddressFamily;

import cs.system.net.sockets.SelectMode;

import cs.system.net.sockets.SocketException;
import cs.system.net.sockets.SocketFlags;
import cs.system.net.sockets.SocketType;
import cs.system.net.sockets.Socket in NativeSocket;

/**
 * `Server` for the C# target (heaps-drive spec §1), on System.Net.Sockets directly. Haxe's own
 * `sys.net.Socket` there cannot serve the channel: its `output.writeBytes` is `Output`'s byte-at-a-time
 * loop over `NetworkStream.WriteByte`, one syscall a byte: a 1.5 MB reply held the UI thread for more
 * than 15 s there, and 40 ms here. A full non-blocking socket is an exception, not `Blocked`. The behaviour is
 * `Server`'s — one client, another answered `busy`, polled once a frame, replies queued in an outbox.
 */
class CsTransport implements ITransport {
	static inline var MAX_ACCEPTS_PER_TICK = 8;

	public var port(default, null):Int;

	var listener:NativeSocket;
	var token:String;
	var dispatch:Request->Outcome;
	var clock:Void->Float;
	var session:Null<Session> = null;
	var closed = false;

	public function new(token:String, dispatch:Request->Outcome, clock:Void->Float) {
		this.token = token;
		this.dispatch = dispatch;
		this.clock = clock;
		listener = new NativeSocket(AddressFamily.InterNetwork, SocketType.Stream, cs.system.net.sockets.ProtocolType.Tcp);
		listener.Bind(new IPEndPoint(IPAddress.Loopback, 0));
		listener.Blocking = false;   // an Accept after a Poll must not wait if the connection has since been reset
		listener.Listen(2);
		port = cast(listener.LocalEndPoint, IPEndPoint).Port;
	}

	public function tick():Void {
		if (closed) return;   // the app keeps calling a tick it has no way to remove
		if (session != null) {
			session.tick();
			if (session.closed) endSession();
		}
		var accepted = 0;
		while (accepted++ < MAX_ACCEPTS_PER_TICK && listener.Poll(0, SelectMode.SelectRead)) {
			var s = listener.Accept();
			if (session != null && !session.closed) refuse(s);
			else {
				endSession();
				session = new Session(new CsConnection(s), token, dispatch, clock);
				session.onTimeout = () -> onTimeout();
				session.tick();
				if (session.closed) endSession();
			}
		}
	}

	public var connected(get, never):Bool;
	function get_connected():Bool return session != null && !session.closed;

	public var onClientGone:Void->Void = () -> {};
	public var onTimeout:Void->Void = () -> {};

	function endSession():Void {
		if (session == null) return;
		var s = session;
		session = null;
		s.close();
		onClientGone();
	}

	function refuse(s:NativeSocket):Void {
		try {
			s.Blocking = false;
			var line = Bytes.ofString(haxe.Json.stringify({id: 0, ok: false, code: "busy", error: "another client is connected"}) + "\n");
			s.Send(line.getData(), 0, line.length, SocketFlags.None);
		} catch (_:Dynamic) {}
		try s.Close() catch (_:Dynamic) {}
	}

	public function close():Void {
		if (closed) return;
		closed = true;
		try listener.Close() catch (_:Dynamic) {}
		endSession();
	}
}

/** `SocketConnection` (see Server.hx) over a System.Net.Sockets socket: the same limits, never waits. */
class CsConnection implements IConnection {
	// The limits are SocketConnection's (Server.hx); copied, not referenced, so nothing of sys.net is compiled for C#.
	public static inline var MAX_READ_PER_TICK = 256 * 1024;
	public static inline var MAX_PARTIAL = 1 << 20;
	public static inline var MAX_OUTBOX = 4 << 20;

	var socket:NativeSocket;
	var partial:Bytes = Bytes.alloc(0);
	var outbox:Bytes = Bytes.alloc(0);
	var outPos:Int = 0;
	var gone:Bool = false;
	var socketClosed = false;

	public function new(socket:NativeSocket) {
		this.socket = socket;
		socket.Blocking = false;
	}

	public function receive():Null<String> {
		if (gone) return null;
		drain();
		if (gone) return null;
		var got = new haxe.io.BytesBuffer();
		got.add(partial);
		var read = 0;
		var buf = Bytes.alloc(4096);
		while (read < MAX_READ_PER_TICK) {
			var n = readSome(buf);
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

	/** Compared by name: the extern enum Haxe makes of SocketError has no WouldBlock field to compare with. */
	static inline function wouldBlock(e:SocketException):Bool
		return Std.string(e.SocketErrorCode) == "WouldBlock";

	/** Bytes read into `buf` now; -1 when there are none yet; 0 when the client has closed. */
	function readSome(buf:Bytes):Int {
		try {
			if (!socket.Poll(0, SelectMode.SelectRead)) return -1;
			return socket.Receive(buf.getData(), 0, buf.length, SocketFlags.None);
		} catch (e:SocketException) {
			return wouldBlock(e) ? -1 : 0;
		} catch (_:Dynamic) {
			return 0;
		}
	}

	/** Bytes of `b` written now; 0 when the socket takes none yet; -1 when the client has gone. */
	function writeSome(b:Bytes, pos:Int, len:Int):Int {
		try {
			if (!socket.Poll(0, SelectMode.SelectWrite)) return 0;
			return socket.Send(b.getData(), pos, len, SocketFlags.None);
		} catch (e:SocketException) {
			return wouldBlock(e) ? 0 : -1;
		} catch (_:Dynamic) {
			return -1;
		}
	}

	function drain():Void {
		while (!gone && outPos < outbox.length) {
			var n = writeSome(outbox, outPos, outbox.length - outPos);
			if (n < 0) { gone = true; return; }
			if (n == 0) return;
			outPos += n;
		}
		if (outPos == outbox.length && outPos > 0) { outbox = Bytes.alloc(0); outPos = 0; }
	}

	public function close():Void {
		if (socketClosed) return;
		socketClosed = true;
		drain();
		gone = true;
		try socket.Close() catch (_:Dynamic) {}
	}
}
#end
