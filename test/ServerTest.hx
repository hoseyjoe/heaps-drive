package;

import haxe.Json;
import utest.Assert;
import drive.Protocol;
import drive.Server;

/** The drive channel over a real loopback socket (heaps-drive spec §1). */
class ServerTest extends utest.Test {
    var server:Server;

    function setup() server = new Server("T", r -> r.cmd == "echo" ? Done(r.args) : Failed("bad_request", "no"), haxe.Timer.stamp);
    function teardown() server.close();

    function connect():sys.net.Socket {
        var s = new sys.net.Socket();
        s.connect(new sys.net.Host("127.0.0.1"), server.port);
        return s;
    }

    /** Pumps the server until `s` has a whole line to read, or 3 s pass. */
    function readLine(s:sys.net.Socket):Null<String> {
        var deadline = haxe.Timer.stamp() + 3, got = new haxe.io.BytesBuffer();
        while (haxe.Timer.stamp() < deadline) {
            server.tick();
            if (sys.net.Socket.select([s], null, null, 0.01).read.length > 0) {
                var b = haxe.io.Bytes.alloc(1);
                var n = try s.input.readBytes(b, 0, 1) catch (_:Dynamic) 0;
                if (n == 0) return got.length == 0 ? null : got.getBytes().toString();
                if (b.get(0) == 10) return got.getBytes().toString();
                got.addByte(b.get(0));
            }
        }
        return null;
    }

    function testItListensOnLoopbackAndAnswers() {
        Assert.isTrue(server.port > 0);
        var c = connect();
        c.output.writeString(Json.stringify({id: 1, token: "T", cmd: "echo", args: {v: 7}}) + "\n");
        var r:Dynamic = Json.parse(readLine(c));
        Assert.equals(7, r.result.v);
        c.close();
    }

    function testASecondClientIsBusy() {
        var a = connect();
        a.output.writeString(Json.stringify({id: 1, token: "T", cmd: "echo"}) + "\n");
        readLine(a);
        var b = connect();
        var r:Dynamic = Json.parse(readLine(b));
        Assert.equals("busy", r.code);
        a.close(); b.close();
    }

    function testAClientThatLeftFreesTheChannel() {
        var a = connect();
        a.output.writeString(Json.stringify({id: 1, token: "T", cmd: "echo"}) + "\n");
        readLine(a);
        a.close();
        for (_ in 0...20) { server.tick(); Sys.sleep(0.01); }
        var b = connect();
        b.output.writeString(Json.stringify({id: 2, token: "T", cmd: "echo", args: {ok: 1}}) + "\n");
        var r:Dynamic = Json.parse(readLine(b));
        Assert.equals(1, r.result.ok, "the new client is served, not refused as busy");
        b.close();
    }

    function testOnClientGoneFiresWhenAClientDisconnects() {
        var gone = 0;
        server.onClientGone = () -> gone++;
        var a = connect();
        a.output.writeString(Json.stringify({id: 1, token: "T", cmd: "echo"}) + "\n");
        readLine(a);
        Assert.equals(0, gone, "not while connected");
        a.close();
        for (_ in 0...20) { server.tick(); Sys.sleep(0.01); }
        Assert.equals(1, gone, "once, when the client left");
    }

    /**
        Writes `line` over and over from a non-blocking `c` that never reads, ticking the server
        between writes, until the server lets the client go or 10 s pass. Returns the slowest tick
        (seconds) and whether the client was let go.
    **/
    function flood(c:sys.net.Socket, line:String):{slowest:Float, closed:Bool} {
        var gone = 0;
        server.onClientGone = () -> gone++;
        c.setBlocking(false);
        var bytes = haxe.io.Bytes.ofString(line), pos = 0, slowest = 0.0;
        var deadline = haxe.Timer.stamp() + 10;
        while (gone == 0 && haxe.Timer.stamp() < deadline) {
            for (_ in 0...16) {   // as much as the socket takes now
                var n = try c.output.writeBytes(bytes, pos, bytes.length - pos) catch (_:Dynamic) 0;
                if (n == 0) break;
                pos = (pos + n) % bytes.length;
            }
            var t = haxe.Timer.stamp();
            server.tick();
            slowest = Math.max(slowest, haxe.Timer.stamp() - t);
        }
        return {slowest: slowest, closed: gone > 0};
    }

    function testAClientWithoutATokenFloodingAndNeverReadingIsLetGo() {
        var c = connect();
        var r = flood(c, "{not json, and no token}\n");
        Assert.isTrue(r.closed, "the session closed");
        Assert.isTrue(r.slowest < 0.25, "every tick returned promptly (slowest " + r.slowest + " s)");
        Assert.isFalse(server.connected);
        c.close();
    }

    function testAnAuthenticatedClientThatNeverReadsIsLetGoWithoutStallingATick() {
        var c = connect();
        var big = "x";
        while (big.length < 200 * 1024) big += big;
        var r = flood(c, Json.stringify({id: 1, token: "T", cmd: "echo", args: {s: big}}) + "\n");
        Assert.isTrue(r.closed, "the session closed once its outbox passed the cap");
        Assert.isTrue(r.slowest < 0.25, "every tick returned promptly (slowest " + r.slowest + " s)");
        c.close();
    }

    function testALineThatNeverEndsIsLetGo() {
        var c = connect();
        c.output.writeString(Json.stringify({id: 1, token: "T", cmd: "echo"}) + "\n");
        readLine(c);
        var r = flood(c, "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx");
        Assert.isTrue(r.closed, "a line past the cap closes the session");
        Assert.isTrue(r.slowest < 0.25, "every tick returned promptly (slowest " + r.slowest + " s)");
        c.close();
    }

    function testCloseClosesTheClientSocket() {
        var c = connect();
        c.output.writeString(Json.stringify({id: 1, token: "T", cmd: "echo"}) + "\n");
        readLine(c);
        server.close();
        var deadline = haxe.Timer.stamp() + 3, eof = false;
        while (!eof && haxe.Timer.stamp() < deadline)
            if (sys.net.Socket.select([c], null, null, 0.05).read.length > 0)
                eof = try { c.input.readBytes(haxe.io.Bytes.alloc(16), 0, 16); false; } catch (_:Dynamic) true;
        Assert.isTrue(eof, "the client sees its connection end");
        c.close();
        setup();   // teardown closes it again
    }

    function testAMultiByteCharacterSplitAcrossReadsSurvives() {
        var c = connect();
        var bytes = haxe.io.Bytes.ofString(Json.stringify({id: 1, token: "T", cmd: "echo", args: {s: "café"}}) + "\n");
        // Cut between the two bytes of é (0xC3 0xA9), wherever the encoder put it in the line.
        var cut = -1;
        for (i in 0...bytes.length - 1) if (bytes.get(i) == 0xC3 && bytes.get(i + 1) == 0xA9) cut = i + 1;
        Assert.isTrue(cut > 0, "the line carries a raw two-byte é");
        c.output.writeBytes(bytes, 0, cut);
        c.output.flush();
        for (_ in 0...10) { server.tick(); Sys.sleep(0.01); }
        c.output.writeBytes(bytes, cut, bytes.length - cut);
        var r:Dynamic = Json.parse(readLine(c));
        Assert.equals("café", r.result.s);
        c.close();
    }

    function testItListensOnLoopbackOnly() {
        // The port answers on 127.0.0.1 ...
        var s = connect();
        s.close();
        // ... and the listener is bound to that address, not to every interface.
        var host = @:privateAccess server.listener.host();
        Assert.equals("127.0.0.1", host.host.toString());
    }
}
