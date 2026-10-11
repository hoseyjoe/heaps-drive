import drive.Commands;
import drive.Finder;
import drive.Protocol;
import utest.Assert;
import Fakes;

class CommandsTest extends utest.Test {
	var targets:FakeTargets;
	var input:FakeInput;
	var window:FakeWindow;
	var host:FakeHost;
	var now:Float;
	var commands:Commands;

	function setup() {
		targets = new FakeTargets();
		input = new FakeInput();
		window = new FakeWindow();
		host = new FakeHost();
		now = 100;
		commands = new Commands(new Finder([targets]), input, null, window, host, () -> now);
	}

	function run(cmd:String, ?args:Dynamic):Outcome return commands.dispatch({id: 1, cmd: cmd, args: args == null ? {} : args});

	/** Polls a Later until it answers, at most `n` times. */
	function settle(o:Outcome, n = 10):Outcome {
		switch (o) {
			case Later(poll, _, _):
				for (_ in 0...n) { var r = poll(); if (r != null) return r; }
				return o;
			case _: return o;
		}
	}

	function code(o:Outcome):String return switch (o) { case Failed(c, _, _): c; case _: "ok"; };

	function testClickInjectsAtTheHitsCentre() {
		targets.table.set("text:Go", Found(FakeTargets.hit("go", 15, 25)));
		switch (run("click", {target: "text:Go"})) {
			case Done(r): Assert.equals(15, r.x); Assert.equals(25, r.y);
			case other: Assert.fail("" + other);
		}
		Assert.same(["click 15,25 0 false"], input.log);
	}

	function testACoveredTargetIsOccludedAndNothingIsInjected() {
		targets.table.set("text:Under", Found(FakeTargets.hit("under", 5, 5, "Interactive cover")));
		var o = run("click", {target: "text:Under"});
		Assert.equals("occluded", code(o));
		switch (o) { case Failed(_, error, _): Assert.isTrue(error.indexOf("cover") >= 0, error); case _: }
		Assert.same([], input.log);
	}

	function testForceClicksACoveredTarget() {
		targets.table.set("text:Under", Found(FakeTargets.hit("under", 5, 5, "Interactive cover")));
		Assert.equals("ok", code(run("click", {target: "text:Under", force: true})));
		Assert.same(["click 5,5 0 false"], input.log);
	}

	function testADisabledTargetIsRefused() {
		targets.table.set("#off", Found(FakeTargets.hit("off", 5, 5, null, true)));
		Assert.equals("disabled", code(run("click", {target: "#off"})));
		Assert.same([], input.log);
	}

	function testRightAndDoubleReachTheInput() {
		targets.table.set("#m", Found(FakeTargets.hit("m", 1, 2)));
		run("click", {target: "#m", right: true, double: true});
		Assert.same(["click 1,2 1 true"], input.log);
	}

	function testMissingAndAmbiguousTargets() {
		targets.table.set("text:X", Missing("nothing"));
		targets.table.set("text:Y", Many([FakeTargets.node("a"), FakeTargets.node("b")]));
		Assert.equals("not_found", code(run("click", {target: "text:X"})));
		Assert.equals("ambiguous", code(run("click", {target: "text:Y"})));
		Assert.equals("bad_request", code(run("click", {})));
	}

	function testAnAppConditionIsAskedFirst() {
		var o = run("wait", {condition: {ready: true}});
		switch (o) {
			case Later(poll, deadline, seen):
				Assert.isNull(poll());
				Assert.equals("ready=false", seen());
				Assert.equals(now + Commands.DEFAULT_TIMEOUT_MS / 1000, deadline);
				host.ready = true;
				Assert.equals("ok", code(poll()));
			case other: Assert.fail("" + other);
		}
	}

	function testWaitRefusesUnknownConditionsAndBadTimeouts() {
		Assert.equals("bad_request", code(run("wait", {condition: {banana: 1}})));
		Assert.equals("bad_request", code(run("wait", {})));
		Assert.equals("bad_request", code(run("wait", {condition: {ready: true}, timeoutMs: Commands.MAX_TIMEOUT_MS + 1})));
	}

	function testWaitExistsAndGone() {
		targets.table.set("text:Go", Missing("not yet"));
		targets.table.set("text:Nope", Missing("never there"));
		var o = run("wait", {condition: {exists: "text:Go"}});
		switch (o) {
			case Later(poll, _, _):
				Assert.isNull(poll());
				targets.table.set("text:Go", Found(FakeTargets.hit("go", 1, 1)));
				Assert.equals("ok", code(poll()));
			case other: Assert.fail("" + other);
		}
		Assert.equals("ok", code(settle(run("wait", {condition: {gone: "text:Nope"}}))), "gone holds when nothing is found");
	}

	function testWaitRefusesATargetNoFinderRecognises() {
		for (kind in ["gone", "exists"]) {
			var cond:Dynamic = {};
			Reflect.setField(cond, kind, "banana");
			var o = run("wait", {condition: cond});
			Assert.equals("bad_request", code(o), kind);
			switch (o) { case Failed(_, error, _): Assert.isTrue(error.indexOf("banana") >= 0 && error.indexOf("#id") >= 0, error); case _: }
		}
		Assert.equals("bad_request", code(run("wait", {condition: {text: "banana", equals: "x"}})));
	}

	function testWaitTextNeedsEqualsOrContains() {
		targets.table.set("text:Go", Found(FakeTargets.hit("go", 1, 1)));
		var o = run("wait", {condition: {text: "text:Go"}});
		Assert.equals("bad_request", code(o), "a text condition with nothing to compare could only time out");
		switch (o) { case Failed(_, error, _): Assert.isTrue(error.indexOf("equals") >= 0 && error.indexOf("contains") >= 0, error); case _: }
	}

	function testResizeAnswersOnceTheWindowHasTheSize() {
		switch (settle(run("resize", {w: 1000, h: 450}))) {
			case Done(r): Assert.equals(1000, r.w); Assert.equals(450, r.h);
			case other: Assert.fail("" + other);
		}
		Assert.equals("bad_request", code(run("resize", {w: 10, h: 450})));
		Assert.equals("bad_request", code(run("resize", {w: "wide", h: 450})));
	}

	function testStatePassesItsArgsToTheHost() {
		Assert.equals("ok", code(run("state", {hint: true})));
		Assert.isTrue(host.lastStateArgs.hint == true);
		var bare = new Commands(new Finder([targets]), input, null, null, null, () -> now);
		Assert.equals("bad_request", code(bare.dispatch({id: 1, cmd: "state", args: {}})));
	}

	function testKeysAreHeldAcrossAFrameAndClipboardIsRefused() {
		switch (settle(run("key", {name: "Ctrl+A"}))) {
			case Done(_): Assert.same(["down 1", "down 65", "up 65", "up 1"], input.log);
			case other: Assert.fail("" + other);
		}
		input.log = [];
		Assert.equals("bad_request", code(run("key", {name: "Ctrl+C"})));
		Assert.same([], input.log, "a clipboard combination is refused before any key goes down");
		Assert.equals("bad_request", code(run("key", {name: "Hyper"})));
	}

	function testKeyAnswersTheFocusOnlyThroughTheHook() {
		switch (settle(run("key", {name: "A"}))) {
			case Done(r): Assert.same({}, r, "no hook: nothing about the focus");
			case other: Assert.fail("" + other);
		}
		commands.focused = () -> "name";
		switch (settle(run("key", {name: "A"}))) {
			case Done(r): Assert.equals("name", r.focused);
			case other: Assert.fail("" + other);
		}
	}

	function testDragPushesMovesAndReleases() {
		targets.table.set("#a", Found(FakeTargets.hit("a", 0, 0)));
		switch (settle(run("drag", {from: "#a", to: {x: 20, y: 0}}), 30)) {
			case Done(_):
				Assert.equals("push 0,0 0", input.log[1]);
				Assert.equals("release 20,0 0", input.log[input.log.length - 1]);
			case other: Assert.fail("" + other);
		}
	}

	function testUnknownCommand() {
		Assert.equals("bad_request", code(run("dance")));
	}
}
