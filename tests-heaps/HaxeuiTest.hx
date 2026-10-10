import drive.Commands;
import drive.Finder;
import drive.Node;
import haxe.ui.HaxeUIApp;
import haxe.ui.components.Button;
import haxe.ui.components.CheckBox;
import haxe.ui.components.Label;
import haxe.ui.components.TextField;
import haxe.ui.containers.HBox;
import haxe.ui.containers.VBox;
import Steps.*;

/** The HaxeUI finder on the heaps backend (heaps-drive spec §1 Finders) — Simplified's TargetsTest
    against the new hit shape — and clicks and typing going in through hxd.Window.event. */
class HaxeuiTest {
	static var goClicks = 0;
	static var targets:drive.haxeui.Targets;

	public static function main() {
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
			var ghost = new Button(); ghost.id = "ghost"; ghost.text = "Ghost"; ghost.hidden = true; root.addComponent(ghost);
			var off = new Button(); off.id = "off"; off.text = "Off"; off.disabled = true; root.addComponent(off);
			var show = new CheckBox(); show.id = "show"; show.text = "Show it"; root.addComponent(show);
			var pw = new TextField(); pw.id = "pw"; pw.password = true; pw.text = "hunter2"; root.addComponent(pw);
			var name = new TextField(); name.id = "name"; root.addComponent(name);
			app.addComponent(root);
			app.start();
			var scene = haxe.ui.core.Screen.instance.scene;
			targets = new drive.haxeui.Targets(scene);
			var w = hxd.Window.getInstance();
			Steps.commands = new Commands(new Finder([targets]), new drive.heaps.Input(w), new drive.heaps.Shot(scene),
				new drive.heaps.HeapsWindow(w), null, haxe.Timer.stamp);
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
				case Many(c): expectEqual(2, c.length, "candidates");
				case other: fail("ambiguous: " + other);
			}
			switch (targets.resolve({target: "text:Delete", within: "#boxB"}, false)) {
				case Found(_): expect(true, "within");
				case other: fail("within: " + other);
			}
		});
		check("resolve: a checkbox's inner label collapses into it", () -> expectFound(targets.resolve("text:Show it", false), "show", "checkbox"));
		check("resolve: hidden, missing, and not mine", () -> {
			expect(targets.resolve("#ghost", false).match(Missing(_)), "a hidden component is not found");
			expectFound(targets.resolve("#ghost", true), "ghost", "includeHidden finds it");
			expect(targets.resolve("#nothing", false).match(Missing(_)), "no match is Missing");
			expect(targets.resolve("name:x", false).match(Unknown), "name: is not the HaxeUI finder's");
			expect(targets.resolve({target: "text:Go", within: "name:x"}, false).match(Unknown), "a name: within is not the HaxeUI finder's");
		});
		check("resolve: a password's text never leaves", () -> {
			expect(targets.resolve("text:hunter2", false).match(Missing(_)), "text: never matches a password");
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
			case other: fail("bounds: " + other);
		});
		check("tree: hidden components are left out, disabled ones kept", () -> {
			var t = targets.tree(null, false);
			expect(!contains(t, "ghost"), "no ghost");
			expect(contains(t, "off"), "off is there");
		});
		send("click: #go through hxd.Window.event", "click", {target: "#go"}, o -> done(o));
		check("click: HaxeUI fired onClick once", () -> expectEqual(1, goClicks, "go clicks"));
		send("click: a disabled button is refused", "click", {target: "#off"}, o -> expectFailed(o, "disabled"));
		send("type: into #name", "type", {target: "#name", text: "Ada"}, o -> {
			var r = done(o);
			if (r != null) expectEqual("Ada", r.text, "typed text");
		});
		send("key: answers what has the focus", "key", {name: "End"}, o -> {
			var r = done(o);
			if (r != null) expectEqual("name", r.focused, "focused");
		});
	}

	static function contains(nodes:Array<Node>, id:String):Bool {
		for (n in nodes) if (n.id == id || (n.children != null && contains(n.children, id))) return true;
		return false;
	}

	static function expectFound(r:Resolved, id:String, what:String)
		switch (r) { case Found(h): expectEqual(id, h.node.id, what); case other: fail(what + ": " + other); }
}
