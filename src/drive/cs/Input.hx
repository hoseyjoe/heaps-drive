package drive.cs;

#if (haxeui_cs && haxeui_cs_drive)
import haxe.ui.backend.cs.native.Native.AppDriver;

/**
 * Input handed to the window as raw Avalonia events through AppDriver (haxeui-cs), which is where
 * the OS's own input arrives: nothing reaches the OS's input queue, so the user's mouse, keyboard
 * and focus are never involved. Positions are window units, as AppDriver takes them. heaps-drive's
 * buttons are 0 left and 1 right; AppDriver's are 0 left, 1 middle, 2 right.
 */
class Input implements drive.IInput {
	/** Part of a key name -> the name of Avalonia's Key. A letter is its own name, a digit `d` is `D<d>`. */
	static var KEYS:Map<String, String> = [
		"Enter" => "Enter", "Tab" => "Tab", "Escape" => "Escape", "Backspace" => "Back",
		"Delete" => "Delete", "Up" => "Up", "Down" => "Down", "Left" => "Left", "Right" => "Right",
		"Home" => "Home", "End" => "End", "PageUp" => "PageUp", "PageDown" => "PageDown",
		"Insert" => "Insert", "F2" => "F2", "Space" => "Space",
		"Ctrl" => "LeftCtrl", "Shift" => "LeftShift", "Alt" => "LeftAlt",
		// Single punctuation characters with a key of their own (US layout). Shifted ones, like `!`
		// or `:`, are refused: `type` puts characters in.
		"-" => "OemMinus", "=" => "OemPlus", "`" => "OemTilde", "[" => "OemOpenBrackets",
		"]" => "OemCloseBrackets", ";" => "OemSemicolon", "'" => "OemQuotes", "\\" => "OemPipe",
		"," => "OemComma", "." => "OemPeriod", "/" => "OemQuestion"
	];

	/** Keys and buttons pressed and not yet released, so a client that vanishes mid-key or mid-drag
	    can be undone (`releaseHeld`). */
	var heldKeys:Array<Int> = [];
	var heldButtons:Array<Int> = [];
	/** Where the pointer is now: key and release events have no position of their own. */
	var pointerX = 0.0;
	var pointerY = 0.0;
	/** The high half of a character outside the BMP, waiting for its low half. */
	var highSurrogate = 0;

	public function new() {}

	static inline function native(button:Int):Int return button == 1 ? 2 : 0;

	public function move(x:Float, y:Float):Void {
		pointerX = x;
		pointerY = y;
		AppDriver.MouseMove(x, y);
	}

	public function push(x:Float, y:Float, button:Int):Void {
		var b = native(button);
		if (heldButtons.indexOf(b) < 0) heldButtons.push(b);
		pointerX = x;
		pointerY = y;
		AppDriver.MouseDown(x, y, b);
	}

	public function release(x:Float, y:Float, button:Int):Void {
		var b = native(button);
		heldButtons.remove(b);
		pointerX = x;
		pointerY = y;
		AppDriver.MouseUp(x, y, b);
	}

	/** Lets go where the pointer is NOW, not where the button went down: an abandoned drag that had
	    moved off its source releases outside it, and never clicks it. */
	public function releaseHeld():Void {
		highSurrogate = 0;
		for (k in heldKeys.copy()) keyUp(k);
		for (b in heldButtons.copy()) {
			heldButtons.remove(b);
			AppDriver.MouseUp(pointerX, pointerY, b);
		}
	}

	public function click(x:Float, y:Float, button:Int, double:Bool):Void {
		move(x, y);
		for (_ in 0...(double ? 2 : 1)) { push(x, y, button); release(x, y, button); }
	}

	/** Positive notches scroll down (heaps' sign); AppDriver's positive deltaY scrolls up. */
	public function wheel(x:Float, y:Float, notches:Int):Void {
		move(x, y);
		for (_ in 0...Std.int(Math.abs(notches))) AppDriver.Wheel(x, y, notches > 0 ? -1 : 1, 0);
	}

	public function keyDown(code:Int):Void {
		if (heldKeys.indexOf(code) < 0) heldKeys.push(code);
		AppDriver.KeyDown(code);
	}

	public function keyUp(code:Int):Void {
		heldKeys.remove(code);
		AppDriver.KeyUp(code);
	}

	/** `charCode` is a UTF-16 unit, as Commands sends them; a character outside the BMP arrives as its
	    two halves, and goes in as one text. A half with no partner goes in as U+FFFD. */
	public function text(charCode:Int):Void {
		if (highSurrogate != 0) {
			var high = highSurrogate;
			highSurrogate = 0;
			if (charCode >= 0xDC00 && charCode <= 0xDFFF) {
				// Haxe's fromCharCode takes a code point, never a half of one.
				AppDriver.Text(String.fromCharCode(((high - 0xD800) << 10) + (charCode - 0xDC00) + 0x10000));
				return;
			}
			AppDriver.Text(String.fromCharCode(0xFFFD));
		}
		if (charCode >= 0xD800 && charCode <= 0xDBFF) highSurrogate = charCode;
		else if (charCode >= 0xDC00 && charCode <= 0xDFFF) AppDriver.Text(String.fromCharCode(0xFFFD));
		else AppDriver.Text(String.fromCharCode(charCode));
	}

	public function keyCode(part:String):Null<Int> {
		var name = KEYS.get(part);
		if (name == null && part.length == 1) {
			var c = part.toUpperCase().charCodeAt(0);
			if (c >= "A".code && c <= "Z".code) name = String.fromCharCode(c);
			else if (c >= "0".code && c <= "9".code) name = "D" + String.fromCharCode(c);
		}
		if (name == null) return null;
		var code = AppDriver.KeyCode(name);
		return code < 0 ? null : code;
	}

	/** Copy, cut and paste (Ctrl+C/X/V, Ctrl+Insert, Shift+Insert) reach the user's OS clipboard
	    through the text field: the channel never sends them. */
	public function touchesClipboard(codes:Array<Int>):Bool {
		var ctrl = codes.indexOf(AppDriver.KeyCode("LeftCtrl")) >= 0, shift = codes.indexOf(AppDriver.KeyCode("LeftShift")) >= 0;
		var insert = AppDriver.KeyCode("Insert");
		for (k in codes) {
			if (ctrl && (k == AppDriver.KeyCode("C") || k == AppDriver.KeyCode("X") || k == AppDriver.KeyCode("V") || k == insert)) return true;
			if (shift && k == insert) return true;
		}
		return false;
	}
}
#end
