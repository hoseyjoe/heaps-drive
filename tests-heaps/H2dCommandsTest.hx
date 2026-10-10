import drive.Commands;
import drive.Finder;
import Steps.*;

/**
 * The h2d finder and the heaps input, end to end (heaps-drive spec §3): a letterbox with a scale AND
 * an offset (an 800x600 window on a 300x300 canvas: x2, a 100 px bar each side), a rotated container,
 * a button under a cover, a small button in front of a big sibling, a label over no button, a hidden
 * button and a draggable square. Every press goes in through hxd.Window.event.
 */
class H2dCommandsTest extends hxd.App {
	static function main() new H2dCommandsTest();

	var counts = new Map<String, Int>();
	var font:h2d.Font;

	function bump(what:String) counts.set(what, count(what) + 1);
	function count(what:String):Int return counts.exists(what) ? counts.get(what) : 0;

	function button(parent:h2d.Object, label:String, x:Float, y:Float, w:Float, h:Float) {
		var g = new h2d.Graphics(parent);
		g.beginFill(0x445566); g.drawRect(x, y, w, h); g.endFill();
		var t = new h2d.Text(font, parent);
		t.text = label;
		t.textAlign = Center;
		t.x = x + w / 2;
		t.y = y + (h - t.textHeight) / 2;
		var i = new h2d.Interactive(w, h, parent);
		i.x = x; i.y = y;
		i.onClick = _ -> bump(label);
	}

	override function init() {
		hxd.Window.getInstance().title = "H2dCommandsTest";
		s2d.scaleMode = LetterBox(300, 300);
		font = hxd.res.DefaultFont.get();

		button(s2d, "Go", 10, 10, 80, 30);

		// A rotated container: JoeClash's landscape board is one.
		var turned = new h2d.Object(s2d);
		turned.x = 200; turned.y = 40; turned.rotation = Math.PI / 2;
		var cell = new h2d.Interactive(40, 20, turned);
		cell.name = "cell";
		cell.onClick = _ -> bump("cell");

		// A button with a cover drawn after it: the cover is on top.
		button(s2d, "Under", 10, 100, 80, 30);
		var cover = new h2d.Interactive(100, 50, s2d);
		cover.y = 90; cover.name = "cover";
		cover.onClick = _ -> bump("cover");

		// A small button in front of a big sibling: the finder takes the smallest Interactive.
		var bg = new h2d.Interactive(300, 100, s2d);
		bg.y = 180;
		bg.onClick = _ -> bump("bg");
		button(s2d, "Small", 20, 200, 60, 24);

		// A label over no button at all (OverworldMap's city names sit below their node).
		var floating = new h2d.Text(font, s2d);
		floating.text = "Floating"; floating.x = 150; floating.y = 150;

		var hiddenBox = new h2d.Object(s2d);
		hiddenBox.visible = false;
		button(hiddenBox, "Ghost", 200, 200, 60, 24);

		// A draggable square that counts pushes and releases.
		var drag = new h2d.Interactive(30, 30, s2d);
		drag.x = 250; drag.y = 250; drag.name = "drag";
		drag.onPush = _ -> bump("push");
		drag.onRelease = _ -> bump("release");

		// A green square at a known place, for the screenshot.
		var mark = new h2d.Graphics(s2d);
		mark.beginFill(0x00FF00); mark.drawRect(260, 10, 20, 20); mark.endFill();

		var w = hxd.Window.getInstance();
		Steps.commands = new Commands(new Finder([new drive.h2d.Targets(s2d)]), new drive.heaps.Input(w),
			new drive.heaps.Shot(s2d), new drive.heaps.HeapsWindow(w), null, haxe.Timer.stamp);
		define();
	}

	function define() {
		send("find: a label over its button is found, in window pixels", "find", {target: "text:Go"}, o -> {
			var n = done(o);
			if (n == null) return;
			expectEqual("h2d", n.source, "source");
			// 10,10 80x30 on the canvas = 100 + 10*2, 0 + 10*2, 160x60 in the window.
			expectEqual(120, n.x, "x"); expectEqual(20, n.y, "y");
			expectEqual(160, n.w, "w"); expectEqual(60, n.h, "h");
			expectEqual("Go", n.text, "the Interactive reports its label");
		});
		send("click: text:Go", "click", {target: "text:Go"}, o -> done(o));
		check("click: Go fired once", () -> expectEqual(1, count("Go"), "Go clicks"));

		send("click: name:cell inside a rotated container", "click", {target: "name:cell"}, o -> done(o));
		check("click: the rotated cell fired once", () -> expectEqual(1, count("cell"), "cell clicks"));

		send("click: a covered button is occluded", "click", {target: "text:Under"}, o -> {
			var error = expectFailed(o, "occluded");
			expect(error != null && error.indexOf("cover") >= 0, "the error names the cover: " + error);
		});
		check("click: nothing fired under or on the cover", () -> {
			expectEqual(0, count("Under"), "Under clicks"); expectEqual(0, count("cover"), "cover clicks");
		});
		send("click: force reaches the cover, not the button", "click", {target: "text:Under", force: true}, o -> done(o));
		check("click: force hit the cover", () -> {
			expectEqual(1, count("cover"), "cover clicks"); expectEqual(0, count("Under"), "Under clicks");
		});

		send("click: the small button, not its big sibling", "click", {target: "text:Small"}, o -> done(o));
		check("click: Small fired, bg did not", () -> {
			expectEqual(1, count("Small"), "Small clicks"); expectEqual(0, count("bg"), "bg clicks");
		});

		send("find: a label over no button is not a target", "find", {target: "text:Floating"}, o -> expectFailed(o, "not_found"));
		send("find: a hidden button is not found", "find", {target: "text:Ghost"}, o -> expectFailed(o, "not_found"));
		send("find: includeHidden finds it", "find", {target: "text:Ghost", includeHidden: true}, o -> done(o));

		// Released on the square itself: released elsewhere, heaps calls onReleaseOutside instead.
		send("drag: push on the square, release on it", "drag", {from: "name:drag", to: "name:drag"}, o -> done(o));
		check("drag: the square saw one push and one release", () -> {
			expectEqual(1, count("push"), "pushes"); expectEqual(1, count("release"), "releases");
		});
		check("releaseHeld: start a drag and abandon it", () -> {
			var o = Steps.commands.dispatch({id: 1, cmd: "drag", args: {from: "name:drag", to: "name:drag"}});
			expect(o.match(Later(_, _, _)), "a drag is Later");
			Steps.commands.releaseHeld();
		});
		check("releaseHeld: the held button was let go", () -> expectEqual(2, count("release"), "releases"));

		send("shot: the whole canvas", "shot", {file: "bin/test-heaps/whole.png"}, o -> {
			var r = done(o);
			if (r == null) return;
			expectEqual(300, r.w, "canvas width"); expectEqual(300, r.h, "canvas height");
		});
		check("shot: the green mark is where it was drawn", () -> {
			var px = new drive.heaps.Shot(s2d).pixels(null);
			var c = px.getPixel(270, 20) & 0xFFFFFF;
			// Green survives an RGB/BGR swap, so the channel order does not matter.
			expectEqual(0x00FF00, c, "the pixel at 270,20");
		});
		send("shot: within crops to the target", "shot", {file: "bin/test-heaps/small.png", within: "text:Small"}, o -> {
			var r = done(o);
			if (r == null) return;
			expect(Math.abs(r.w - 60) <= 2 && Math.abs(r.h - 24) <= 2, 'cropped to the 60x24 button, got ${r.w}x${r.h}');
		});

		check("ambiguous: a second Go", () -> button(s2d, "Go", 10, 50, 80, 30));
		send("click: two Go buttons are ambiguous", "click", {target: "text:Go"}, o -> expectFailed(o, "ambiguous"));

		send("resize: 600x600", "resize", {w: 600, h: 600}, o -> {
			var r = done(o);
			if (r != null) { expectEqual(600, r.w, "w"); expectEqual(600, r.h, "h"); }
		});
		send("find: after the resize the letterbox has no bar", "find", {target: "text:Small"}, o -> {
			var n = done(o);
			if (n != null) expectEqual(40, n.x, "x = 20 * 2, no offset");
		});
		send("click: still lands after the resize", "click", {target: "text:Small"}, o -> done(o));
		check("click: Small fired again", () -> expectEqual(2, count("Small"), "Small clicks"));
	}

	override function update(dt:Float) Steps.tick();
}
