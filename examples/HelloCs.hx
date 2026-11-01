import drive.IDriveHost;
import haxe.ui.HaxeUIApp;
import haxe.ui.Toolkit;
import haxe.ui.backend.cs.native.Native.Host;
import haxe.ui.components.Button;
import haxe.ui.components.Label;
import haxe.ui.components.TextField;
import haxe.ui.containers.Absolute;
import haxe.ui.containers.ListView;
import haxe.ui.core.Screen;
import haxe.ui.data.ArrayDataSource;
import haxe.ui.events.KeyboardEvent;
import haxe.ui.events.MouseEvent;
#if (haxeui_cs_drive && !haxeui_cs_headless)
import haxe.ui.backend.cs.native.Native.AppDriver;
#end

/**
 * The smallest driven HaxeUI app on C#: a button, a text field, a scrolling list and a label, and
 * what each saw. tools/selftest-cs.mjs launches it (headless, or in a real window put off every
 * display) and drives it through drive.cs. `--scale 1.5` sets Toolkit.scale.
 */
class HelloCs implements IDriveHost {
	var app:HaxeUIApp;
	var go:Button;
	var field:TextField;
	var list:ListView;
	var count:Label;
	var clicks = 0;
	var rightClicks = 0;
	var wheel = 0;
	var pressed = 0;
	var released = 0;
	var keysDown = 0;
	var keysUp = 0;
	var pointer = {x: -1.0, y: -1.0};

	static function main() {
		drive.cs.OffScreen.install();
		var app = new HaxeUIApp({width: 640, height: 480, title: "HelloCs"});
		app.ready(function() {
			var scale = Sys.args().indexOf("--scale");
			if (scale >= 0) Toolkit.scale = Std.parseFloat(Sys.args()[scale + 1]);
			var hello = new HelloCs(app);
			var dir = Sys.getEnv("DRIVE_DIR");
			drive.cs.Channel.start(hello, [new drive.haxeui.Targets()], dir == null ? "." : dir);
			app.start();
			#if haxeui_cs_headless
			drive.cs.Channel.runHeadless();
			#end
		});
	}

	function new(app:HaxeUIApp) {
		this.app = app;
		var root = new Absolute();
		root.percentWidth = 100;
		root.percentHeight = 100;
		go = new Button();
		go.id = "go";
		go.text = "Go";
		go.left = 20;
		go.top = 20;
		go.width = 120;
		go.height = 40;
		go.backgroundColor = 0xFF0000;
		go.onClick = e -> { clicks++; count.text = "clicks: " + clicks; };
		go.registerEvent(MouseEvent.RIGHT_CLICK, e -> rightClicks++);
		root.addComponent(go);
		field = new TextField();
		field.id = "name";
		field.left = 20;
		field.top = 80;
		field.width = 200;
		root.addComponent(field);
		list = new ListView();
		list.id = "list";
		list.left = 20;
		list.top = 130;
		list.width = 200;
		list.height = 120;
		var items = new ArrayDataSource<Dynamic>();
		for (i in 0...40) items.add({text: "Item " + i});
		list.dataSource = items;
		list.registerEvent(MouseEvent.MOUSE_WHEEL, e -> wheel++);
		root.addComponent(list);
		count = new Label();
		count.id = "count";
		count.text = "clicks: 0";
		count.left = 20;
		count.top = 270;
		root.addComponent(count);
		app.addComponent(root);
		// What the window as a whole saw, whichever component the input was for.
		var screen = Screen.instance;
		screen.registerEvent(MouseEvent.MOUSE_DOWN, e -> pressed++);
		screen.registerEvent(MouseEvent.MOUSE_UP, e -> released++);
		var moved = function(e:MouseEvent) pointer = {x: e.screenX * Toolkit.scaleX, y: e.screenY * Toolkit.scaleY};
		screen.registerEvent(MouseEvent.MOUSE_MOVE, moved);
		go.registerEvent(MouseEvent.MOUSE_MOVE, moved);   // the button holds the pointer while it is pressed
		screen.registerEvent(KeyboardEvent.KEY_DOWN, e -> keysDown++);
		screen.registerEvent(KeyboardEvent.KEY_UP, e -> keysUp++);
	}

	public function condition(cond:Dynamic):Null<{check:Void->Bool, seen:Void->Dynamic}> {
		if (cond.clicks != null) return {check: () -> clicks >= cond.clicks, seen: () -> (clicks : Dynamic)};
		if (cond.crash == true) {
			// From a haxe.Timer, not from this handler (Session would turn that into an `internal` error):
			// an error nobody catches, for the selftest's crash run.
			haxe.Timer.delay(() -> throw "HelloCs: a crash on demand", 100);
			return {check: () -> false, seen: () -> "crashing"};
		}
		return null;
	}

	public function state(args:Dynamic):Dynamic {
		var s:Dynamic = {
			clicks: clicks, rightClicks: rightClicks, wheel: wheel, pressed: pressed, released: released,
			keysDown: keysDown, keysUp: keysUp, scroll: list.vscrollPos, text: field.text, selection: field.selectionEndIndex - field.selectionStartIndex, pointer: pointer,
			client: {w: Math.round(Host.ClientWidth), h: Math.round(Host.ClientHeight)}, renderScaling: Host.RenderScaling
		};
		#if (haxeui_cs_drive && !haxeui_cs_headless)
		// The window must never be the user's: not active, and not on any display (unless DRIVE_VISIBLE=1).
		s.windowActive = AppDriver.WindowIsActive;
		s.onDisplay = AppDriver.WindowIsOnADisplay;
		#end
		return s;
	}

	public function quit():Void {
		#if haxeui_cs_headless
		Host.Exit(0);
		#else
		app.exit();
		#end
	}
}
