import drive.cs.Input;
import haxe.ui.HaxeUIApp;
import haxe.ui.backend.cs.TestDriver;
import haxe.ui.backend.cs.native.Native.Host;
import haxe.ui.components.TextField;
import haxe.ui.containers.Absolute;
import haxe.ui.core.Screen;

/**
 * drive.cs.Input's text, straight (no channel), in a headless HaxeUI app: a character outside the BMP
 * arrives as two UTF-16 units and goes in as one; half a character that ends a text is dropped by the
 * next click, so it never lands in whatever has the focus later. `haxe tests-cs/input.hxml` builds,
 * runs, and exits 0 with `input-probe: ok`.
 */
class InputProbe {
	static var failures = 0;

	static function main() {
		var app = new HaxeUIApp();
		app.ready(function() {
			var root = new Absolute();
			root.percentWidth = 100;
			root.percentHeight = 100;
			var field = new TextField();
			field.left = 20;
			field.top = 20;
			field.width = 200;
			root.addComponent(field);
			app.addComponent(root);
			TestDriver.pump(3);
			var input = new Input();
			var p = {x: 20 + 100.0, y: 20 + field.height / 2};

			input.click(p.x, p.y, 0, false);
			TestDriver.pump(2);
			input.text(0xD83D);
			input.text(0xDE00);   // U+1F600, as its two UTF-16 units
			TestDriver.pump(2);
			check(field.text == "\u{1F600}", "a pair goes in as one character, got " + show(field.text));

			field.text = "";
			TestDriver.pump(2);
			input.click(p.x, p.y, 0, false);
			input.text("a".code);
			input.text(0xD83D);   // half a character ends the text
			TestDriver.pump(2);
			input.click(p.x, p.y, 0, false);   // the next command's click
			input.text("b".code);
			TestDriver.pump(2);
			check(field.text == "ab", "half a character that ended a text is not put in later, got " + show(field.text));

			field.text = "";
			TestDriver.pump(2);
			input.click(p.x, p.y, 0, false);
			input.text(0xD83D);
			input.text("c".code);   // a high half followed by something else in one text: U+FFFD, then c
			input.text(0xDE00);     // a low half with no high one
			TestDriver.pump(2);
			check(field.text == "\u{FFFD}c\u{FFFD}", "halves with no partner are U+FFFD, got " + show(field.text));

			input.text(0xD83D);
			input.releaseHeld();
			input.text("d".code);
			TestDriver.pump(2);
			check(field.text.substr(-1) == "d" && field.text.indexOf("\u{FFFD}", 3) < 0, "releaseHeld drops a pending half, got " + show(field.text));

			Sys.println(failures == 0 ? "input-probe: ok" : "input-probe: " + failures + " failed");
			Host.Exit(failures == 0 ? 0 : 1);
		});
	}

	static function check(ok:Bool, what:String) {
		if (!ok) {
			failures++;
			Sys.println("input-probe: FAIL " + what);
		}
	}

	static function show(s:String):String {
		return [for (i in 0...s.length) StringTools.hex(StringTools.fastCodeAt(s, i), 4)].join(" ");
	}
}
