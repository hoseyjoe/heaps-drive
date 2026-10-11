package drive;

import drive.Node;
import drive.Protocol;

/**
 * The channel's commands (heaps-drive spec §1): Simplified's command table, speaking only to the
 * seams — a Finder for targets, an IInput for presses, an IShot, an IWindow — so it carries no
 * backend of its own and builds headless. Every position it hands IInput is a window pixel a finder
 * computed.
 */
class Commands {
	public static inline var DEFAULT_TIMEOUT_MS = 5000;
	public static inline var MAX_TIMEOUT_MS = 60000;
	/** A drag is one move a frame for this many frames. */
	static inline var DRAG_FRAMES = 20;

	public var onQuit:Void->Void = () -> {};

	var finder:Finder;
	var input:IInput;
	var shooter:Null<IShot>;
	var window:Null<IWindow>;
	var host:Null<IDriveHost>;
	var clock:Void->Float;

	public function new(finder:Finder, input:IInput, shooter:Null<IShot>, window:Null<IWindow>, host:Null<IDriveHost>, clock:Void->Float) {
		this.finder = finder;
		this.input = input;
		this.shooter = shooter;
		this.window = window;
		this.host = host;
		this.clock = clock;
	}

	public function dispatch(r:Request):Outcome {
		var a:Dynamic = r.args == null ? {} : r.args;
		return switch (r.cmd) {
			case "tree": tree(a);
			case "find": withTarget(a, false, h -> Done(h.node));
			case "click": withTarget(a, true, h -> click(h, a));
			case "type": withTarget(a, true, h -> type(h, a));
			case "key": key(a);
			case "wheel":
				if (!Std.isOfType(a.notches, Float)) Failed("bad_request", "wheel needs a numeric notches (negative scrolls up)")
				else withTarget(a, false, h -> { input.wheel(h.cx, h.cy, Std.int(a.notches)); Done({}); });
			case "drag": drag(a);
			case "shot": shot(a);
			case "state": host == null ? Failed("bad_request", "no app state in this build") : Done(host.state(a));
			case "wait": wait(a);
			case "resize": resize(a);
			case "quit": quit();
			case _: Failed("bad_request", "unknown command '" + r.cmd + "'");
		};
	}

	/** Lets go of every key and button an interrupted `key` or `drag` left held (the client went away). */
	public function releaseHeld():Void input.releaseHeld();

	function failure(r:Resolved):Outcome {
		return switch (r) {
			case Missing(why): Failed("not_found", why);
			case Many(c): Failed("ambiguous", c.length + " things match", c);
			case Unknown: Failed("not_found", "no finder takes that target");
			case Found(_): Failed("internal", "a found target reported as a failure");
		};
	}

	function withTarget(a:Dynamic, action:Bool, then:Hit->Outcome):Outcome {
		if (a.target == null) return Failed("bad_request", "this command needs a target");
		var spec:Dynamic = a.within == null ? a.target : {target: a.target, within: a.within};
		var r = finder.resolve(spec, a.includeHidden == true);
		return switch (r) {
			case Found(h): action && h.node.disabled ? Failed("disabled", "the target is disabled") : then(h);
			case _: failure(r);
		};
	}

	function click(h:Hit, a:Dynamic):Outcome {
		if (a.force != true) {
			var top = h.occluder();
			if (top != null) return Failed("occluded", "the target is covered by " + top + " (force: true clicks anyway)", [h.node]);
		}
		input.click(h.cx, h.cy, a.right == true ? 1 : 0, a.double == true);
		return Done({x: Math.round(h.cx), y: Math.round(h.cy)});
	}

	function type(h:Hit, a:Dynamic):Outcome {
		if (!Std.isOfType(a.text, String)) return Failed("bad_request", "type needs text");
		var text:String = a.text;
		var clicked = click(h, a);
		if (!clicked.match(Done(_))) return clicked;
		// The text goes in two frames after the click, not with it: an empty field with a
		// placeholder holds the placeholder as its text until the focus the click gives it has been
		// validated, and characters typed before that are appended to the placeholder.
		// (The first poll runs in this same tick.) A password's text is never in an answer.
		var secret = h.node.passwordLength != null;
		var polls = 0;
		return Later(() -> {
			if (++polls < 3) return null;
			if (polls == 3) { for (i in 0...text.length) input.text(StringTools.fastCodeAt(text, i)); return null; }
			if (polls < 5) return null;
			return Done(secret ? {length: text.length} : {text: h.text()});
		}, clock() + DEFAULT_TIMEOUT_MS / 1000, () -> secret ? null : h.text());
	}

	function key(a:Dynamic):Outcome {
		if (!Std.isOfType(a.name, String)) return Failed("bad_request", "key needs a name");
		var codes:Array<Int> = [];
		for (part in (a.name : String).split("+")) {
			var code = input.keyCode(part);
			if (code == null) return Failed("bad_request", "unknown key '" + part + "' (a named key, a letter, a digit or one of - = ` [ ] ; ' \\ , . /; type puts other characters in)");
			codes.push(code);
		}
		if (input.touchesClipboard(codes)) return Failed("bad_request", "the channel never touches the user's clipboard: " + a.name + " is not sent");
		// Heaps queues a key event until the frame's scene update, but hxd.Key tracks modifiers at
		// once: releasing Ctrl in the same frame as Ctrl+A would hide it from a text field. So the
		// keys are held across a frame and released on a later one.
		for (k in codes) input.keyDown(k);
		codes.reverse();
		var polls = 0;
		return Later(() -> {
			if (++polls == 1) return null;
			if (polls == 2) { for (k in codes) input.keyUp(k); return null; }
			#if haxeui_core
			return Done({focused: drive.haxeui.Targets.focused()});
			#else
			return Done({});
			#end
		}, clock() + DEFAULT_TIMEOUT_MS / 1000, () -> polls);
	}

	/** Push at `from`, one move a frame for DRAG_FRAMES frames, release at `to`. */
	function drag(a:Dynamic):Outcome {
		var f = point(a.from), t = point(a.to);
		if (f.failed != null) return f.failed;
		if (t.failed != null) return t.failed;
		var from = f.at, to = t.at;
		input.move(from.x, from.y);
		input.push(from.x, from.y, 0);
		var step = 0;
		return Later(() -> {
			step++;
			var k = Math.min(step / DRAG_FRAMES, 1);
			input.move(from.x + (to.x - from.x) * k, from.y + (to.y - from.y) * k);
			if (step < DRAG_FRAMES) return null;
			input.release(to.x, to.y, 0);
			return Done({});
		}, clock() + DEFAULT_TIMEOUT_MS / 1000, () -> step);
	}

	/** {x, y} in window pixels as given; anything else is a target. */
	function point(p:Dynamic):{at:Null<{x:Float, y:Float}>, failed:Null<Outcome>} {
		var bad = {at: null, failed: Failed("bad_request", "drag needs from and to (targets, or {x, y} in window pixels)")};
		if (p == null) return bad;
		if (!Std.isOfType(p, String) && Reflect.isObject(p) && Std.isOfType(p.x, Float) && Std.isOfType(p.y, Float))
			return {at: {x: p.x, y: p.y}, failed: null};
		var r = finder.resolve(p, false);
		return switch (r) {
			case Found(h): {at: {x: h.cx, y: h.cy}, failed: null};
			case _: {at: null, failed: failure(r)};
		};
	}

	function tree(a:Dynamic):Outcome {
		var t = finder.tree(a.within, a.includeHidden == true);
		return t == null ? Failed("not_found", "nothing matches within " + haxe.Json.stringify(a.within)) : Done({tree: t});
	}

	function describe(r:Resolved):Dynamic {
		return switch (r) {
			case Found(h): h.node;
			case Missing(why): why;
			case Many(c): c.length + " things match";
			case Unknown: "no finder takes it";
		};
	}

	/** Polls a condition once a frame: the app's own first, then exists / gone / text. */
	function wait(a:Dynamic):Outcome {
		var ms:Int = Std.isOfType(a.timeoutMs, Int) ? a.timeoutMs : DEFAULT_TIMEOUT_MS;
		if (ms < 0 || ms > MAX_TIMEOUT_MS) return Failed("bad_request", "timeoutMs is 0 to " + MAX_TIMEOUT_MS);
		var cond:Dynamic = a.condition;
		if (cond == null || !Reflect.isObject(cond)) return Failed("bad_request", "wait needs a condition: exists, gone, text, or one of the app's");
		var c = host == null ? null : host.condition(cond);
		if (c == null) {
			// With nothing to compare, a text wait could only ever time out.
			if (cond.exists == null && cond.gone == null && cond.text != null && cond.equals == null && cond.contains == null)
				return Failed("bad_request", "a text condition needs equals or contains");
			var target:Dynamic = cond.exists != null ? cond.exists : cond.gone != null ? cond.gone : cond.text;
			if (target != null && !finder.recognises(target))
				return Failed("bad_request", "no finder takes the target " + haxe.Json.stringify(target)
					+ ": a target is #id, text:Exact, text~:part, name:objectName or one of the app's prefixes");
			c = generic(cond);
		}
		if (c == null) return Failed("bad_request", "unknown condition " + haxe.Json.stringify(cond));
		var check = c.check, seen = c.seen;
		return Later(() -> check() ? Done({seen: seen()}) : null, clock() + ms / 1000, seen);
	}

	function generic(cond:Dynamic):Null<{check:Void->Bool, seen:Void->Dynamic}> {
		if (cond.exists != null) {
			var t:Dynamic = cond.exists;
			return {check: () -> finder.resolve(t, false).match(Found(_)), seen: () -> describe(finder.resolve(t, false))};
		}
		if (cond.gone != null) {
			var t:Dynamic = cond.gone;
			return {check: () -> finder.resolve(t, false).match(Missing(_)), seen: () -> describe(finder.resolve(t, false))};
		}
		if (cond.text != null) {
			var t:Dynamic = cond.text;
			var current = () -> switch (finder.resolve(t, false)) { case Found(h): h.text(); case _: null; };
			return {check: () -> {
				var v = current();
				v != null && (cond.equals != null ? v == cond.equals : cond.contains != null && v.indexOf(cond.contains) >= 0);
			}, seen: current};
		}
		return null;
	}

	function shot(a:Dynamic):Outcome {
		#if sys
		if (shooter == null) return Failed("bad_request", "no screenshots in this build");
		if (!Std.isOfType(a.file, String)) return Failed("bad_request", "shot needs a file");
		var crop:Null<{x:Float, y:Float, w:Float, h:Float}> = null;
		if (a.within != null) {
			var r = finder.resolve(a.within, false);
			switch (r) {
				case Found(h): crop = {x: h.node.x, y: h.node.y, w: h.node.w, h: h.node.h};
				case _: return failure(r);
			}
		}
		var got = shooter.capture(crop);
		if (got == null) return Failed("bad_request", "no part of " + haxe.Json.stringify(a.within) + " is inside the window");
		var file = sys.FileSystem.absolutePath(a.file);
		sys.FileSystem.createDirectory(haxe.io.Path.directory(file));
		sys.io.File.saveBytes(file, got.png);
		return Done({file: file, w: got.w, h: got.h});
		#else
		return Failed("bad_request", "shot needs a sys target");
		#end
	}

	function resize(a:Dynamic):Outcome {
		if (window == null) return Failed("bad_request", "this build cannot resize its window");
		if (!Std.isOfType(a.w, Int) || !Std.isOfType(a.h, Int)) return Failed("bad_request", "resize needs whole w and h");
		var w:Int = a.w, h:Int = a.h;
		if (w < 100 || h < 100 || w > 8000 || h > 8000) return Failed("bad_request", "resize takes 100 to 8000 pixels a side");
		window.resize(w, h);
		// The app sees a resize on its next frame and may rebuild on the one after: answered once the
		// window reports the size and two more frames have passed.
		var settled = 0;
		return Later(() -> {
			var s = window.size();
			if (s.w != w || s.h != h) return null;
			return ++settled >= 3 ? Done(s) : null;
		}, clock() + DEFAULT_TIMEOUT_MS / 1000, () -> window.size());
	}

	/** Answers first, then exits on a later frame so the reply reaches the client. */
	function quit():Outcome {
		haxe.Timer.delay(() -> { onQuit(); if (host != null) host.quit(); }, 100);
		return Done({});
	}
}
