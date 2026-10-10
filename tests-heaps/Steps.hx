import drive.Commands;
import drive.Protocol;

/**
 * A windowed test as a list of steps a few frames apart, each dispatching a command the way a client
 * would and polling a `Later` once a frame — Simplified's tests-heaps harness. A watchdog fails the
 * run if it never finishes. Prints ok/FAIL per step and exits 0 only when every check passed.
 */
class Steps {
	static inline var FRAMES_BETWEEN_STEPS = 4;
	static inline var MAX_FRAMES = 1200;

	public static var commands:Commands;

	static var steps:Array<{name:String, run:Void->Void}> = [];
	static var stepIndex = 0;
	static var wait = 10;   // a few frames for the first layout before step one
	static var frames = 0;
	static var checks = 0;
	static var failures = 0;
	static var pending:Null<Void->Null<Outcome>> = null;
	static var onAnswer:Null<Outcome->Void> = null;
	static var pendingDeadline = 0.0;

	/** A step that only checks (or changes the scene). */
	public static function check(label:String, run:Void->Void) steps.push({name: label, run: run});

	/** One step: dispatch, and when the command is `Later`, poll it once a frame until it answers. */
	public static function send(label:String, cmd:String, args:Dynamic, answer:Outcome->Void)
		steps.push({name: label, run: () -> {
			var o = commands.dispatch({id: 1, cmd: cmd, args: args});
			switch (o) {
				case Later(poll, deadline, _):
					var first = poll();
					if (first != null) answer(first);
					else { pending = poll; pendingDeadline = deadline; onAnswer = answer; }
				case _: answer(o);
			}
		}});

	public static function tick() {
		frames++;
		if (frames > MAX_FRAMES) {
			Sys.println('FAIL - timed out after $MAX_FRAMES frames at step $stepIndex of ${steps.length}');
			Sys.exit(1);
		}
		if (pending != null) {
			var o = pending();
			if (o != null) {
				var cb = onAnswer; pending = null; onAnswer = null;
				var before = failures;
				try cb(o) catch (e:haxe.Exception) fail("threw " + e.message);
				Sys.println(failures == before ? "ok   - (answered)" : "FAIL - (answered)");
				wait = FRAMES_BETWEEN_STEPS;
			} else if (haxe.Timer.stamp() > pendingDeadline) { fail("a Later command timed out"); pending = null; }
			return;
		}
		if (--wait > 0) return;
		if (stepIndex >= steps.length) {
			Sys.println('$checks checks, $failures failed');
			Sys.exit(failures == 0 ? 0 : 1);
		}
		var s = steps[stepIndex++];
		var before = failures;
		try s.run() catch (e:haxe.Exception) fail(s.name + " threw " + e.message);
		Sys.println((failures == before ? "ok   - " : "FAIL - ") + s.name);
		wait = FRAMES_BETWEEN_STEPS;
	}

	public static function done(o:Outcome):Dynamic {
		switch (o) {
			case Done(r): return r;
			case other: fail("expected Done, got " + other); return null;
		}
	}

	public static function expectFailed(o:Outcome, code:String):Null<String>
		return switch (o) {
			case Failed(c, error, _): expectEqual(code, c, "failure code"); error;
			case other: fail("expected Failed " + code + ", got " + other); null;
		};

	public static function expect(cond:Bool, what:String) { checks++; if (!cond) fail(what); }

	public static function expectEqual<T>(expected:T, actual:T, what:String) {
		checks++;
		if (expected != actual) fail('$what: expected $expected, got $actual');
	}

	public static function fail(message:String) { failures++; Sys.println("       " + message); }
}
