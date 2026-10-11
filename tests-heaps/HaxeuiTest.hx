import drive.Commands;
import drive.Finder;
import drive.Node;
import haxe.ui.HaxeUIApp;
import haxe.ui.components.Button;
import haxe.ui.components.CheckBox;
import haxe.ui.components.HorizontalSlider;
import haxe.ui.components.Label;
import haxe.ui.components.TextField;
import haxe.ui.containers.Frame;
import haxe.ui.containers.HBox;
import haxe.ui.containers.ScrollView;
import haxe.ui.containers.VBox;
import haxe.ui.events.MouseEvent;
import Steps.*;

/** The HaxeUI finder on the heaps backend (heaps-drive spec §1 Finders) — Simplified's TargetsTest
    and the HaxeUI half of its CommandsTest, against the new hit shape — with every click, key and
    character going in through hxd.Window.event. */
class HaxeuiTest {
	static var goClicks = 0;
	static var sameClicks = 0;
	static var rightClicks = 0;
	static var twiceClicks = 0;
	static var targets:drive.haxeui.Targets;
	static var secret:TextField;
	static var hinted:TextField;
	static var side:VBox;
	static var slider:HorizontalSlider;
	static var scroll:ScrollView;

	public static function main() {
		drive.heaps.OffScreen.install();   // never on the user's screen (DRIVE_VISIBLE=1 to watch)
		var app = new HaxeUIApp();
		app.ready(() -> {
			hxd.Window.getInstance().title = "HaxeuiTest";
			var root = new VBox(); root.id = "root";
			var go = new Button(); go.id = "go"; go.text = "Go"; go.onClick = _ -> goClicks++; root.addComponent(go);
			var label = new Label(); label.text = "Pump P-101 tripped"; root.addComponent(label);
			for (name in ["boxA", "boxB"]) {
				var box = new HBox(); box.id = name;
				var del = new Button(); del.text = "Delete"; box.addComponent(del);
				root.addComponent(box);
			}
			for (_ in 0...2) { var same = new Button(); same.text = "Same"; same.onClick = _ -> sameClicks++; root.addComponent(same); }
			var ghost = new Button(); ghost.id = "ghost"; ghost.text = "Ghost"; ghost.hidden = true; root.addComponent(ghost);
			var off = new Button(); off.id = "off"; off.text = "Off"; off.disabled = true; root.addComponent(off);
			var frame = new Frame(); frame.id = "confirmFrame"; frame.text = "Confirm";
			var inner = new Button(); inner.id = "confirmButton"; inner.text = "Confirm"; frame.addComponent(inner);
			root.addComponent(frame);
			var show = new CheckBox(); show.id = "show"; show.text = "Show it"; root.addComponent(show);
			var pw = new TextField(); pw.id = "pw"; pw.password = true; pw.text = "hunter2"; root.addComponent(pw);
			var name = new TextField(); name.id = "name"; root.addComponent(name);
			secret = new TextField(); secret.id = "secret"; secret.password = true; root.addComponent(secret);
			hinted = new TextField(); hinted.id = "hinted"; hinted.placeholder = "name@example.com"; root.addComponent(hinted);
			// A box filled from its dataSource, as inline XML does it: the <item-renderer> stays a child
			// as the rows' template, hidden by HaxeUI without `hidden` being set.
			var rows = new VBox(); rows.id = "rows";
			var template = new haxe.ui.core.ItemRenderer();
			var rowBtn = new Button(); rowBtn.id = "rowBtn"; template.addComponent(rowBtn);
			rows.addComponent(template);
			rows.dataSource = new haxe.ui.data.ArrayDataSource<Dynamic>();
			rows.dataSource.add({rowBtn: {text: "Row"}});
			root.addComponent(rows);
			// A second column, so everything is inside the window. One root component:
			// FocusManager.focus answers for the top root only.
			var outer = new HBox(); outer.addComponent(root);
			side = new VBox(); side.id = "side";
			slider = new HorizontalSlider(); slider.id = "slider"; slider.width = 200; slider.min = 0; slider.max = 100; slider.pos = 0;
			side.addComponent(slider);
			scroll = new ScrollView(); scroll.id = "scroll"; scroll.width = 160; scroll.height = 80;
			var lines = new VBox();
			for (i in 0...30) { var l = new Label(); l.text = "Line " + i; lines.addComponent(l); }
			scroll.addComponent(lines);
			side.addComponent(scroll);
			var menu = new Button(); menu.id = "menuBtn"; menu.text = "Menu";
			menu.registerEvent(MouseEvent.RIGHT_CLICK, _ -> rightClicks++);
			side.addComponent(menu);
			var twice = new Button(); twice.id = "twiceBtn"; twice.text = "Twice"; twice.onClick = _ -> twiceClicks++;
			side.addComponent(twice);
			outer.addComponent(side);
			app.addComponent(outer);
			app.start();
			var scene = haxe.ui.core.Screen.instance.scene;
			targets = new drive.haxeui.Targets(scene);
			var w = hxd.Window.getInstance();
			Steps.commands = new Commands(new Finder([targets]), new drive.heaps.Input(w), new drive.heaps.Shot(scene),
				new drive.heaps.HeapsWindow(w), null, haxe.Timer.stamp);
			Steps.commands.focused = drive.haxeui.Targets.focused;   // as Start sets it
			define();
			haxe.MainLoop.add(Steps.tick);
		});
	}

	static function define() {
		check("resolve: by id, exact text and substring", () -> {
			expectFound(targets.resolve("#go", false), "go", "by id");
			expectFound(targets.resolve("text:Go", false), "go", "by exact text");
			switch (targets.resolve("text~:p-101", false)) {
				case Found(h): expectEqual("Pump P-101 tripped", h.node.text, "substring, any case");
				case other: fail("substring: " + other);
			}
		});
		check("resolve: two Delete buttons are Many, within scopes them", () -> {
			switch (targets.resolve("text:Delete", false)) {
				case Many(c):
					expectEqual(2, c.length, "candidates");
					expect(c[0].ambiguousScope != true, "an ambiguous target is not marked as scope");
				case other: fail("ambiguous: " + other);
			}
			switch (targets.resolve({target: "text:Delete", within: "#boxB"}, false)) {
				case Found(_): expect(true, "within");
				case other: fail("within: " + other);
			}
			switch (targets.resolve({target: "#go", within: "text:Delete"}, false)) {
				case Many(c): expect(c.length == 2 && c[0].ambiguousScope == true, "an ambiguous within is marked as the scope being ambiguous");
				case other: fail("ambiguous within: " + other);
			}
		});
		check("resolve: a frame and a button with the same text are two matches", () -> switch (targets.resolve("text:Confirm", false)) {
			case Many(c): expectEqual(2, c.length, "container and child");
			case other: fail("container and child: " + other);
		});
		check("resolve: a checkbox's inner label collapses into it", () -> {
			expectFound(targets.resolve("text:Show it", false), "show", "checkbox");
			expectFound(targets.resolve("text~:show it", false), "show", "substring: collapsed too");
		});
		check("resolve: hidden, missing, and not mine", () -> {
			expect(targets.resolve("#ghost", false).match(Missing(_)), "a hidden component is not found");
			expectFound(targets.resolve("#ghost", true), "ghost", "includeHidden finds it");
			expect(targets.resolve("#nothing", false).match(Missing(_)), "no match is Missing");
			expect(targets.resolve("go", false).match(Unknown), "a bare word is not a target form");
			expect(targets.resolve("name:x", false).match(Unknown), "name: is not the HaxeUI finder's");
			expect(targets.resolve({target: "text:Go", within: "name:x"}, false).match(Unknown), "a name: within is not the HaxeUI finder's");
		});
		check("resolve: a dataSource box's row is found, its template is not", () -> {
			expectFound(targets.resolve("#rowBtn", false), "rowBtn", "the row");
			switch (targets.resolve("#rowBtn", true)) {
				case Many(c): expectEqual(2, c.length, "includeHidden finds the template too");
				case other: fail("template with includeHidden: " + other);
			}
		});
		check("resolve: a password's text never leaves", () -> {
			expect(targets.resolve("text:hunter2", false).match(Missing(_)), "text: never matches a password");
			expect(targets.resolve("text~:hunter", false).match(Missing(_)), "text~: never matches a password");
			switch (targets.resolve("#pw", false)) {
				case Found(h): expect(h.node.text == "" && h.node.passwordLength == 7, "no text, its length");
				case other: fail("password: " + other);
			}
		});
		check("resolve: bounds are window pixels", () -> switch (targets.resolve("#go", false)) {
			case Found(h):
				var c = (cast haxe.ui.core.Screen.instance.rootComponents[0] : haxe.ui.core.Component).findComponent("go", Button);
				expect(Math.abs(h.node.x - c.screenLeft * haxe.ui.Toolkit.scaleX) < 1, "x is screenLeft through an identity viewport");
				expect(h.node.w > 0 && h.node.h > 0, "a size");
				expectEqual("Button", h.node.type, "type");
			case other: fail("bounds: " + other);
		});
		check("tree: hidden components and templates are left out, disabled ones kept", () -> {
			var t = targets.tree(null, false);
			expect(!contains(t, "ghost"), "no ghost");
			expectEqual(1, count(t, "rowBtn"), "the row, not its template");
			expect(contains(t, "off"), "off is there");
		});

		send("click: #go through hxd.Window.event", "click", {target: "#go"}, o -> done(o));
		// HaxeUI delivers a click through callLater, so its effect shows a step later.
		check("click: HaxeUI fired onClick once", () -> expectEqual(1, goClicks, "go clicks"));
		send("click: a disabled button is refused", "click", {target: "#off"}, o -> expectFailed(o, "disabled"));
		send("click: text:Same is ambiguous", "click", {target: "text:Same"}, o -> expectFailed(o, "ambiguous"));
		check("click: no Same button counted a click", () -> expectEqual(0, sameClicks, "Same clicks"));
		send("click: right-click #menuBtn", "click", {target: "#menuBtn", right: true}, o -> done(o));
		check("click: the RIGHT_CLICK handler fired", () -> expectEqual(1, rightClicks, "right clicks"));
		send("click: double-click #twiceBtn", "click", {target: "#twiceBtn", double: true}, o -> done(o));
		// Two clicks, not a DBL_CLICK: haxeui-heaps never fires DBL_CLICK on a component that already
		// listens for CLICK (its MOUSE_UP hook is taken).
		check("click: a double click is two clicks", () -> expectEqual(2, twiceClicks, "clicks"));

		send("type: into #name", "type", {target: "#name", text: "Ada"}, o -> {
			var r = done(o);
			if (r != null) expectEqual("Ada", r.text, "typed text");
		});
		send("key: answers what has the focus", "key", {name: "End"}, o -> {
			var r = done(o);
			if (r != null) expectEqual("name", r.focused, "focused");
		});
		// An empty field holds its placeholder as text until its focus is validated: typed with the
		// focusing click, the text was appended to the placeholder.
		send("type: into an empty field with a placeholder", "type", {target: "#hinted", text: "a@b.c"}, o -> {
			var r = done(o);
			if (r != null) expectEqual("a@b.c", r.text, "the text alone");
			expectEqual("a@b.c", hinted.text, "field text, no placeholder in it");
		});
		send("type: into a password field answers a length only", "type", {target: "#secret", text: "hunter2"}, o -> {
			var r = done(o);
			expect(r != null && r.length == 7, "length 7");
			expect(haxe.Json.stringify(r).indexOf("hunter2") < 0, "the reply does not carry the text");
			expectEqual("hunter2", secret.text, "the field holds it");
		});
		send("tree: a password's text is not in it", "tree", {}, o -> {
			var s = haxe.Json.stringify(done(o));
			expect(s.indexOf("hunter2") < 0, "the tree does not carry hunter2");
			expect(s.indexOf('"passwordLength":7') >= 0, "the tree carries the password's length");
		});
		check("wait: a password's text is \"\" and never equals what it holds", () -> {
			switch (Steps.commands.dispatch({id: 1, cmd: "wait", args: {condition: {text: "#secret", equals: "hunter2"}, timeoutMs: 100}})) {
				case Later(poll, _, seen):
					expect(poll() == null, "the guess does not match");
					expect(haxe.Json.stringify(seen()).indexOf("hunter2") < 0, "what it last saw does not carry the text");
				case other: fail("expected Later, got " + other);
			}
			switch (Steps.commands.dispatch({id: 1, cmd: "wait", args: {condition: {text: "#secret", contains: "hunter"}, timeoutMs: 100}})) {
				case Later(poll, _, _): expect(poll() == null, "a part of the password does not match either");
				case other: fail("expected Later, got " + other);
			}
		});
		send("key: Ctrl+A in the password field", "key", {name: "Ctrl+A"}, o -> {
			var r = done(o);
			if (r != null) expectEqual("secret", r.focused, "focused");
		});
		send("key: Backspace empties the selected password field", "key", {name: "Backspace"}, o -> {
			done(o);
			expectEqual("", secret.text, "secret text after Ctrl+A, Backspace");
		});
		check("releaseHeld: lets go of a key left held", () -> {
			Steps.commands.dispatch({id: 1, cmd: "key", args: {name: "Ctrl+A"}});   // never polled
			expect(hxd.Key.isDown(hxd.Key.CTRL), "Ctrl is held");
			Steps.commands.releaseHeld();
			expect(!hxd.Key.isDown(hxd.Key.CTRL), "Ctrl is released");
		});
		check("key: focus a field without an id", () -> {
			var f = new TextField();
			side.addComponent(f);
			haxe.ui.focus.FocusManager.instance.focus = f;
		});
		send("key: focused answers the type of a component without an id", "key", {name: "End"}, o -> {
			var r = done(o);
			if (r != null) expectEqual("TextField", r.focused, "focused is the type");
		});

		send("drag: the slider's thumb to near its end", "drag", () -> {
			var r:Dynamic = {from: "#end-thumb", to: {
				x: (slider.screenLeft + slider.width * 0.8) * haxe.ui.Toolkit.scaleX,
				y: (slider.screenTop + slider.height / 2) * haxe.ui.Toolkit.scaleY
			}};
			r;
		}, o -> done(o));
		check("drag: the slider moved", () -> expect(slider.pos > 50, "slider pos after the drag: " + slider.pos));
		send("wheel: scroll a ScrollView taller inside than out", "wheel", {target: "#scroll", notches: 3}, o -> done(o));
		check("wheel: the ScrollView scrolled", () -> expect(scroll.vscrollPos > 0, "vscrollPos after 3 notches: " + scroll.vscrollPos));

		// A shot reads the scene back through a render target: none may be left behind.
		var textures = 0;
		check("shot: note the texture count", () -> textures = h3d.Engine.getCurrent().mem.stats().textureCount);
		send("shot: a PNG file", "shot", {file: "bin/test-heaps/haxeui.png"}, o -> {
			var r = done(o);
			expect(r != null && r.w > 0 && r.h > 0 && sys.FileSystem.exists(r.file), "file, w, h");
		});
		send("shot: and again", "shot", {file: "bin/test-heaps/haxeui.png"}, o -> done(o));
		check("shot: no texture is left behind", () -> expectEqual(textures, h3d.Engine.getCurrent().mem.stats().textureCount, "texture count after two shots"));
	}

	static function contains(nodes:Array<Node>, id:String):Bool {
		for (n in nodes) if (n.id == id || (n.children != null && contains(n.children, id))) return true;
		return false;
	}

	static function count(nodes:Array<Node>, id:String):Int {
		var n = 0;
		for (k in nodes) n += (k.id == id ? 1 : 0) + (k.children != null ? count(k.children, id) : 0);
		return n;
	}

	static function expectFound(r:Resolved, id:String, what:String)
		switch (r) { case Found(h): expectEqual(id, h.node.id, what); case other: fail(what + ": " + other); }
}
