package drive.heaps;

import hxd.Key;

/**
 * Input injected as hxd.Events through hxd.Window.event — the path SDL's own input takes — so heaps'
 * SceneEvents (h2d Interactives) and HaxeUI's MouseHelper both handle it as a real press. Positions
 * are WINDOW pixels. The OS cursor is never touched: heaps' own idea of the pointer (curMouseX/Y,
 * private) is set instead, so hover and later events agree. NEVER call hxd.Window.setCursorPos here:
 * it warps the user's real mouse.
 */
class Input implements drive.IInput {
	static var KEYS:Map<String, Int> = [
		"Enter" => Key.ENTER, "Tab" => Key.TAB, "Escape" => Key.ESCAPE, "Backspace" => Key.BACKSPACE,
		"Delete" => Key.DELETE, "Up" => Key.UP, "Down" => Key.DOWN, "Left" => Key.LEFT, "Right" => Key.RIGHT,
		"Home" => Key.HOME, "End" => Key.END, "PageUp" => Key.PGUP, "PageDown" => Key.PGDOWN,
		"Insert" => Key.INSERT, "F2" => Key.F2, "Space" => Key.SPACE,
		"Ctrl" => Key.CTRL, "Shift" => Key.SHIFT, "Alt" => Key.ALT
	];
	/** Single punctuation characters with a key of their own (US layout). Shifted ones, like `!` or
	    `:`, are refused: `type` puts characters in. */
	static var PUNCTUATION:Map<String, Int> = [
		"-" => Key.QWERTY_MINUS, "=" => Key.QWERTY_EQUALS, "`" => Key.QWERTY_TILDE,
		"[" => Key.QWERTY_BRACKET_LEFT, "]" => Key.QWERTY_BRACKET_RIGHT, ";" => Key.QWERTY_SEMICOLON,
		"'" => Key.QWERTY_QUOTE, "\\" => Key.QWERTY_BACKSLASH, "," => Key.QWERTY_COMMA,
		"." => Key.QWERTY_PERIOD, "/" => Key.QWERTY_SLASH
	];

	var window:hxd.Window;
	/** Keys and buttons pressed and not yet released, so a client that vanishes mid-key or mid-drag
	    can be undone (`releaseHeld`). */
	var heldKeys:Array<Int> = [];
	var heldButtons:Array<Int> = [];

	public function new(window:hxd.Window) this.window = window;

	function send(kind:hxd.Event.EventKind, x:Float, y:Float, ?configure:hxd.Event->Void):Void {
		@:privateAccess { window.curMouseX = Std.int(x); window.curMouseY = Std.int(y); }
		var e = new hxd.Event(kind, x, y);
		if (configure != null) configure(e);
		window.event(e);
	}

	public function move(x:Float, y:Float):Void send(EMove, x, y);

	public function push(x:Float, y:Float, button:Int):Void {
		if (heldButtons.indexOf(button) < 0) heldButtons.push(button);
		send(EPush, x, y, e -> e.button = button);
	}

	public function release(x:Float, y:Float, button:Int):Void {
		heldButtons.remove(button);
		send(ERelease, x, y, e -> e.button = button);
	}

	/** Lets go where the pointer is NOW, not where the button went down: an abandoned drag that had
	    moved off its source releases outside it, and never clicks it. */
	public function releaseHeld():Void {
		for (k in heldKeys.copy()) keyUp(k);
		for (b in heldButtons.copy()) release(window.mouseX, window.mouseY, b);
	}

	public function click(x:Float, y:Float, button:Int, double:Bool):Void {
		move(x, y);
		for (_ in 0...(double ? 2 : 1)) { push(x, y, button); release(x, y, button); }
	}

	public function wheel(x:Float, y:Float, notches:Int):Void {
		move(x, y);
		for (_ in 0...Std.int(Math.abs(notches))) send(EWheel, x, y, e -> e.wheelDelta = notches > 0 ? 1 : -1);
	}

	public function keyDown(code:Int):Void {
		if (heldKeys.indexOf(code) < 0) heldKeys.push(code);
		send(EKeyDown, window.mouseX, window.mouseY, e -> e.keyCode = code);
	}

	public function keyUp(code:Int):Void {
		heldKeys.remove(code);
		send(EKeyUp, window.mouseX, window.mouseY, e -> e.keyCode = code);
	}

	public function text(charCode:Int):Void send(ETextInput, window.mouseX, window.mouseY, e -> e.charCode = charCode);

	public function keyCode(part:String):Null<Int> {
		if (KEYS.exists(part)) return KEYS.get(part);
		if (part.length != 1) return null;
		if (PUNCTUATION.exists(part)) return PUNCTUATION.get(part);
		var c = part.toUpperCase().charCodeAt(0);
		return (c >= "A".code && c <= "Z".code) || (c >= "0".code && c <= "9".code) ? c : null;
	}

	/** Copy, cut and paste (Ctrl+C/X/V, Ctrl+Insert, Shift+Insert) reach the user's OS clipboard
	    through h2d.TextInput: the channel never sends them. */
	public function touchesClipboard(codes:Array<Int>):Bool {
		var ctrl = codes.indexOf(Key.CTRL) >= 0, shift = codes.indexOf(Key.SHIFT) >= 0;
		for (k in codes) {
			if (ctrl && (k == "C".code || k == "X".code || k == "V".code || k == Key.INSERT)) return true;
			if (shift && k == Key.INSERT) return true;
		}
		return false;
	}
}
