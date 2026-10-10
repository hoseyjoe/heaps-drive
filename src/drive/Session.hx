package drive;

import haxe.Json;
import drive.Protocol;

/**
 * One automation client (heaps-drive spec §1): reads JSON lines, checks the token, runs each
 * request through `dispatch` in the order received and answers it once. A `Later` outcome is polled
 * each `tick` and holds back the requests behind it until it is answered or times out. Nothing a
 * client sends can throw out of `tick`: a handler that throws is answered `internal`.
 *
 * Until a request has carried the right token, any failure (a malformed line, a missing cmd, a
 * wrong token) is answered and the connection closed: a stranger gets one reply, never a stream.
 * A line longer than MAX_LINE, or more than MAX_QUEUED requests waiting, closes the connection.
 */
class Session {
    /** The longest line accepted, in characters (1 MiB). */
    public static inline var MAX_LINE = 1 << 20;
    /** Requests waiting behind a pending one before the client is cut off. */
    public static inline var MAX_QUEUED = 1000;

    public var closed(default, null):Bool = false;
    /** Whether a request has carried the right token yet. */
    public var authenticated(default, null):Bool = false;
    /** Called when a `Later` times out, so the app can let go of input it left held (a `key` or
        `drag` that never finished). */
    public var onTimeout:Void->Void = () -> {};

    var conn:IConnection;
    var token:String;
    var dispatch:Request->Outcome;
    var clock:Void->Float;
    var buffer:String = "";
    var queue:Array<{id:Int, run:Void->Outcome}> = [];
    var pending:Null<{id:Int, poll:Void->Null<Outcome>, deadline:Float, lastSeen:Void->Dynamic}> = null;

    public function new(conn:IConnection, token:String, dispatch:Request->Outcome, clock:Void->Float) {
        this.conn = conn;
        this.token = token;
        this.dispatch = dispatch;
        this.clock = clock;
    }

    public function tick():Void {
        if (closed) return;
        var got = conn.receive();
        if (got == null) { shut(); return; }
        buffer += got;
        var nl = buffer.indexOf("\n");
        while (nl >= 0 && !closed) {
            var text = buffer.substr(0, nl);
            buffer = buffer.substr(nl + 1);
            if (text.length > MAX_LINE) { shut(); return; }
            if (StringTools.trim(text) != "") accept(text);
            dispatchQueued();   // answered as they come, so only requests behind a pending one wait
            if (queue.length > MAX_QUEUED) { shut(); return; }
            nl = buffer.indexOf("\n");
        }
        if (buffer.length > MAX_LINE) { shut(); return; }
        if (!closed) progress();
    }

    /** Ends the session from outside (the server closing). */
    public function close():Void shut();

    function accept(text:String):Void {
        var o:Dynamic = try Json.parse(text) catch (_:Dynamic) null;
        if (o == null || !Reflect.isObject(o) || Std.isOfType(o, Array)) {
            queue.push({id: 0, run: () -> Failed("bad_request", "a request is one JSON object per line")});
            return;
        }
        var id:Int = Std.isOfType(o.id, Int) ? o.id : 0;
        var givenToken:Dynamic = o.token;
        if (!Std.isOfType(o.cmd, String)) {
            queue.push({id: id, run: () -> Failed("bad_request", "a request needs a cmd")});
            return;
        }
        var request:Request = {id: id, cmd: o.cmd, args: o.args == null ? {} : o.args};
        queue.push({id: id, run: () -> {
            if (givenToken != token) {
                return Failed("unauthorized", "wrong or missing token");
            }
            authenticated = true;
            return dispatch(request);
        }});
    }

    function progress():Void {
        while (!closed) {
            if (pending != null) {
                var p = pending;
                var outcome:Null<Outcome> = try p.poll() catch (e:Dynamic) Failed("internal", Std.string(e));
                if (outcome == null) {
                    if (clock() < p.deadline) return;
                    var seen:Dynamic = try p.lastSeen() catch (_:Dynamic) null;
                    pending = null;
                    try onTimeout() catch (_:Dynamic) {}
                    send({id: p.id, ok: false, code: "timeout", error: "the condition did not hold in time", lastSeen: seen});
                    continue;
                }
                pending = null;
                reply(p.id, outcome);
                continue;
            }
            if (queue.length == 0) return;
            runNext();
        }
    }

    /** Runs queued requests until one is left pending, without polling it: a `Later` is polled once
        per tick, by `progress`, because `key`, `drag` and `type` count frames by their polls. */
    function dispatchQueued():Void {
        while (!closed && pending == null && queue.length > 0) runNext();
    }

    function runNext():Void {
        var item = queue.shift();
        var outcome:Outcome = try item.run() catch (e:Dynamic) Failed("internal", Std.string(e));
        reply(item.id, outcome);
    }

    /** Sends a final outcome, or parks a `Later` as the pending request. */
    function reply(id:Int, outcome:Outcome):Void {
        switch (outcome) {
            case Done(result): send({id: id, ok: true, result: result == null ? {} : result});
            case Failed(code, error, detail):
                var o:Dynamic = {id: id, ok: false, code: code, error: error};
                if (detail != null) o.candidates = detail;
                send(o);
                // Before the token has been seen, any failure ends the connection after its reply.
                if (code == "unauthorized" || !authenticated) shut();
            case Later(poll, deadline, lastSeen): pending = {id: id, poll: poll, deadline: deadline, lastSeen: lastSeen};
        }
    }

    function send(o:Dynamic):Void {
        try conn.send(Json.stringify(o) + "\n") catch (_:Dynamic) shut();
    }

    function shut():Void {
        if (closed) return;
        closed = true;
        pending = null;
        queue = [];
        try conn.close() catch (_:Dynamic) {}
    }
}
