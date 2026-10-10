import drive.IDriveHost;
import drive.IInput;
import drive.ITargets;
import drive.IWindow;
import drive.Node;

/** A finder that answers from a table: target string -> what it resolves to. */
class FakeTargets implements ITargets {
	public var table:Map<String, Resolved> = new Map();
	public function new() {}
	public function resolve(spec:Dynamic, includeHidden:Bool):Resolved {
		var key = Std.isOfType(spec, String) ? spec : haxe.Json.stringify(spec);
		return table.exists(key) ? table.get(key) : Unknown;
	}
	public function tree(within:Dynamic, includeHidden:Bool):Null<Array<Node>> return [];

	public static function node(id:String, ?source = "fake"):Node
		return {source: source, type: "Fake", id: id, text: id, x: 10, y: 20, w: 10, h: 10, disabled: false, focused: false};

	public static function hit(id:String, cx:Float, cy:Float, ?covered:String, ?disabled = false):Hit {
		var n = node(id);
		n.disabled = disabled;
		return {node: n, cx: cx, cy: cy, occluder: () -> covered, text: () -> id};
	}
}

/** Records every input call as one line, e.g. "click 15,25 0 false". */
class FakeInput implements IInput {
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
	/** "Ctrl" is 1; a single letter is its upper-case code; anything else is unknown. */
	public function keyCode(part:String):Null<Int>
		return part == "Ctrl" ? 1 : part.length == 1 ? part.toUpperCase().charCodeAt(0) : null;
	public function touchesClipboard(codes:Array<Int>):Bool return codes.indexOf(1) >= 0 && codes.indexOf("C".code) >= 0;
}

class FakeWindow implements IWindow {
	public var w = 360;
	public var h = 800;
	public function new() {}
	public function resize(w:Int, h:Int) { this.w = w; this.h = h; }
	public function size() return {w: w, h: h};
}

class FakeHost implements IDriveHost {
	public var ready = false;
	public var lastStateArgs:Dynamic = null;
	public function new() {}
	public function condition(cond:Dynamic):Null<{check:Void->Bool, seen:Void->Dynamic}>
		return cond.ready == true ? {check: () -> ready, seen: () -> ("ready=" + ready : Dynamic)} : null;
	public function state(args:Dynamic):Dynamic { lastStateArgs = args; return {screen: "fake"}; }
	public function quit() {}
}
