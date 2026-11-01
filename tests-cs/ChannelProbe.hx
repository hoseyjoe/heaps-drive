import drive.IDriveHost;
import drive.IInput;
import drive.ITargets;
import drive.Node;
import drive.Start;
import haxe.ui.HaxeUIApp;
import haxe.ui.backend.cs.TestDriver;

/** Answers from a table: a spec string -> what it resolves to. Like test/Fakes.hx's FakeTargets. */
class TableTargets implements ITargets {
	public var table:Map<String, Resolved> = new Map();
	public function new() {}
	public function resolve(spec:Dynamic, includeHidden:Bool):Resolved {
		var key = Std.isOfType(spec, String) ? spec : haxe.Json.stringify(spec);
		return table.exists(key) ? table.get(key) : Unknown;
	}
	public function tree(within:Dynamic, includeHidden:Bool):Null<Array<Node>> return [];
}

/** Records every input call as one line, like test/Fakes.hx's FakeInput. */
class RecordingInput implements IInput {
	public var log:Array<String> = [];
	public function new() {}
	public function move(x:Float, y:Float) log.push('move $x,$y');
	public function push(x:Float, y:Float, button:Int) log.push('push $x,$y $button');
	public function release(x:Float, y:Float, button:Int) log.push('release $x,$y $button');
	public function click(x:Float, y:Float, button:Int, double:Bool) log.push('click $x,$y $button $double');
	public function wheel(x:Float, y:Float, notches:Int) log.push('wheel $x,$y $notches');
	public function keyDown(code:Int) log.push('down $code');
	public function keyUp(code:Int) log.push('up $code');
	public function text(charCode:Int) log.push('text $charCode');
	public function releaseHeld() log.push('releaseHeld');
	public function keyCode(part:String):Null<Int> return part.length == 1 ? part.toUpperCase().charCodeAt(0) : null;
	public function touchesClipboard(codes:Array<Int>):Bool return false;
}

/** `state` answers the input log, or with {big: n} a string of n characters; `quit` ends the loop. */
class ProbeHost implements IDriveHost {
	public var quitting = false;
	var input:RecordingInput;
	public function new(input:RecordingInput) this.input = input;
	public function condition(cond:Dynamic):Null<{check:Void->Bool, seen:Void->Dynamic}> return null;
	public function state(args:Dynamic):Dynamic {
		if (args != null && args.big != null) {
			var b = new StringBuf();   // rpad would be quadratic at this size
			for (_ in 0...(args.big : Int)) b.addChar("x".code);
			return {blob: b.toString()};
		}
		return {log: input.log};
	}
	public function quit() quitting = true;
}

/**
 * Serves the drive channel (Start.open) from a headless HaxeUI app, with no window: tools/selftest-channel-cs.mjs
 * drives it. DRIVE_DIR says where drive.json goes.
 */
class ChannelProbe {
	static function main() {
		var app = new HaxeUIApp();
		app.ready(function() {
			var finder = new TableTargets();
			var node:Node = {source: "table", type: "Table", id: "table", text: "table", x: 10, y: 20, w: 300, h: 200, disabled: false, focused: false};
			finder.table.set("#table", Found({node: node, cx: 160, cy: 120, occluder: () -> null, text: () -> "table"}));
			finder.table.set("#never", Missing("never there"));
			var input = new RecordingInput();
			var host = new ProbeHost(input);
			var dir = Sys.getEnv("DRIVE_DIR");
			Start.open(host, [finder], input, null, null, dir == null ? "." : dir);
			while (!host.quitting) {
				TestDriver.pump(1);
				Sys.sleep(0.016);
			}
			// What `quit` does after the host: the cleanup it ran already removed drive.json.
			// A few more frames: the channel's tick must not complain after its cleanup.
			for (_ in 0...10) { TestDriver.pump(1); Sys.sleep(0.016); }
			Sys.println("PROBE: exiting");
			haxe.ui.backend.cs.native.Native.Host.Exit(0);
		});
	}
}
