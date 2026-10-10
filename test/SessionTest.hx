package;

import haxe.Json;
import utest.Assert;
import drive.Protocol;
import drive.Session;

class SessionTest extends utest.Test {
    var conn:FakeConnection;
    var now:Float;
    var released:Bool;
    var polls:Int;
    var session:Session;

    function setup() {
        conn = new FakeConnection();
        now = 100;
        released = false;
        polls = 0;
        session = new Session(conn, "T", dispatch, () -> now);
    }

    /** echo -> its args; hold -> Later until `released`; boom -> throws; slow -> Later that never resolves; throwing -> Later that throws on poll; counted -> Later done at its third poll, counting polls. */
    function dispatch(r:Request):Outcome {
        return switch (r.cmd) {
            case "echo": Done(r.args);
            case "hold": Later(() -> released ? Done({held: true}) : null, now + 5, () -> "still held");
            case "slow": Later(() -> null, now + 1, () -> "last value");
            case "boom": throw "exploded";
            case "throwing": Later(() -> throw "poll exploded", now + 5, () -> null);
            case "counted": Later(() -> ++polls >= 3 ? Done({polls: polls}) : null, now + 5, () -> polls);
            case "pick": Failed("ambiguous", "two match", [{id: "a"}, {id: "b"}]);
            case _: Failed("bad_request", "unknown command '" + r.cmd + "'");
        }
    }

    function line(id:Int, cmd:String, ?args:Dynamic, token = "T"):String
        return Json.stringify({id: id, token: token, cmd: cmd, args: args == null ? {} : args}) + "\n";

    function replies():Array<Dynamic> return [for (s in conn.sent) Json.parse(s)];

    function testOneRequestOneReply() {
        conn.inbox = line(1, "echo", {x: 1});
        session.tick();
        var r = replies();
        Assert.equals(1, r.length);
        Assert.equals(1, r[0].id);
        Assert.isTrue(r[0].ok);
        Assert.equals(1, r[0].result.x);
        Assert.isTrue(StringTools.endsWith(conn.sent[0], "\n"), "one JSON object per line");
    }

    function testLinesSplitAndJoinedAcrossReads() {
        var both = line(1, "echo") + line(2, "echo");
        conn.inbox = both.substr(0, 10);
        session.tick();
        Assert.equals(0, conn.sent.length, "half a line answers nothing");
        conn.inbox = both.substr(10);
        session.tick();
        Assert.same([1, 2], [for (r in replies()) r.id]);
    }

    function testAWrongOrMissingTokenIsRefusedAndClosed() {
        conn.inbox = line(1, "echo", null, "nope");
        session.tick();
        Assert.equals("unauthorized", replies()[0].code);
        Assert.isTrue(session.closed);
        Assert.isTrue(conn.closed);

        setup();
        conn.inbox = Json.stringify({id: 2, cmd: "echo"}) + "\n";
        session.tick();
        Assert.equals("unauthorized", replies()[0].code);
        Assert.isTrue(session.closed);
    }

    function testMalformedLinesAreBadRequestsAndKeepTheConnection() {
        conn.inbox = line(1, "echo") + "{not json\n" + "[1,2]\n" + Json.stringify({id: 3, token: "T"}) + "\n" + line(4, "echo");
        session.tick();
        var r = replies();
        Assert.isTrue(r[0].ok, "the token is seen first");
        Assert.same(["bad_request", "bad_request", "bad_request"], [for (i in 1...4) r[i].code]);
        Assert.equals(0, r[1].id, "an unreadable line has no id");
        Assert.equals(3, r[3].id, "a readable line keeps its id");
        Assert.isTrue(r[4].ok);
        Assert.isFalse(session.closed);
    }

    function testAMalformedLineBeforeTheTokenIsAnsweredAndCloses() {
        conn.inbox = "{not json\n" + line(2, "echo");
        session.tick();
        var r = replies();
        Assert.equals(1, r.length, "one reply, then nothing");
        Assert.equals("bad_request", r[0].code);
        Assert.isTrue(session.closed);
        Assert.isTrue(conn.closed);

        setup();
        conn.inbox = Json.stringify({id: 5, token: "T"}) + "\n";   // the token, but no cmd: never authenticated
        session.tick();
        Assert.equals("bad_request", replies()[0].code);
        Assert.isTrue(session.closed, "a line with no cmd before authentication closes too");
    }

    function testAnOverlongLineCloses() {
        conn.inbox = line(1, "echo");
        session.tick();
        var long = "x";
        while (long.length <= Session.MAX_LINE) long += long;
        conn.inbox = long;   // no newline yet
        session.tick();
        Assert.isTrue(session.closed);
    }

    function testTooManyRequestsWaitingCloses() {
        conn.inbox = line(1, "hold");
        session.tick();
        var b = new StringBuf();
        for (i in 0...Session.MAX_QUEUED + 1) b.add(line(i + 2, "echo"));
        conn.inbox = b.toString();
        session.tick();
        Assert.isTrue(session.closed);
    }

    function testAnUnknownCommandAndAThrowingHandler() {
        conn.inbox = line(1, "nope") + line(2, "boom") + line(3, "echo");
        session.tick();
        var r = replies();
        Assert.equals("bad_request", r[0].code);
        Assert.equals("internal", r[1].code);
        Assert.isTrue(StringTools.contains(r[1].error, "exploded"));
        Assert.isTrue(r[2].ok, "the app keeps serving after a handler throws");
    }

    function testADeferredRequestHoldsBackLaterOnes() {
        conn.inbox = line(1, "hold") + line(2, "echo");
        session.tick();
        Assert.equals(0, conn.sent.length);
        session.tick();
        Assert.equals(0, conn.sent.length, "still held");
        released = true;
        session.tick();
        Assert.same([1, 2], [for (r in replies()) r.id], "answered in the order received");
        Assert.isTrue(replies()[0].result.held);
    }

    /** key, drag and type count frames by polls: requests pipelined behind a Later must not poll it again. */
    function testAPendingRequestIsPolledOncePerTickHoweverManyLinesFollowIt() {
        conn.inbox = line(1, "counted") + line(2, "echo") + line(3, "echo") + line(4, "echo");
        session.tick();
        Assert.equals(1, polls, "one poll in the tick that dispatched it");
        Assert.equals(0, conn.sent.length);
        session.tick();
        Assert.equals(2, polls);
        session.tick();
        Assert.equals(3, polls);
        Assert.same([1, 2, 3, 4], [for (r in replies()) r.id]);
    }

    function testADeferredRequestTimesOutWithWhatItLastSaw() {
        conn.inbox = line(1, "slow");
        session.tick();
        now += 2;
        session.tick();
        var r = replies()[0];
        Assert.equals("timeout", r.code);
        Assert.equals("last value", r.lastSeen);
    }

    function testATimeoutCallsOnTimeoutOnce() {
        var calls = 0;
        session.onTimeout = () -> calls++;
        conn.inbox = line(1, "slow") + line(2, "echo");
        session.tick();
        Assert.equals(0, calls, "not before the deadline");
        now += 2;
        session.tick();
        session.tick();
        Assert.equals(1, calls);
        Assert.same([1, 2], [for (r in replies()) r.id], "the queue moves on after the timeout");
    }

    function testFailureDetailIsSentAsCandidates() {
        conn.inbox = line(1, "pick");
        session.tick();
        var r = replies()[0];
        Assert.equals("ambiguous", r.code);
        Assert.equals(2, (r.candidates : Array<Dynamic>).length);
    }

    function testAClientThatGoesAwayClosesTheSession() {
        conn.gone = true;
        session.tick();
        Assert.isTrue(session.closed);
    }

    function testAWrongTokenInTheSameReadStopsAnswering() {
        conn.inbox = line(1, "echo") + line(2, "echo", null, "nope") + line(3, "echo");
        session.tick();
        var r = replies();
        Assert.equals(2, r.length, "exactly two replies: id 1 ok and the unauthorized one");
        Assert.equals(1, r[0].id);
        Assert.isTrue(r[0].ok);
        Assert.equals(2, r[1].id);
        Assert.equals("unauthorized", r[1].code);
        Assert.isTrue(session.closed);
    }

    function testALaterWhosePollThrowsIsAnsweredAsInternal() {
        conn.inbox = line(1, "throwing") + line(2, "echo");
        session.tick();
        var r = replies();
        Assert.equals(2, r.length);
        Assert.equals(1, r[0].id);
        Assert.equals("internal", r[0].code);
        Assert.isTrue(StringTools.contains(r[0].error, "poll exploded"));
        Assert.equals(2, r[1].id);
        Assert.isTrue(r[1].ok);
    }
}

private class FakeConnection implements IConnection {
    public var inbox:String = "";
    public var sent:Array<String> = [];
    public var closed:Bool = false;
    public var gone:Bool = false;
    public function new() {}
    public function receive():Null<String> {
        if (gone) return null;
        var s = inbox; inbox = ""; return s;
    }
    public function send(text:String):Void sent.push(text);
    public function close():Void closed = true;
}
