package drive.heaps;

#if (drive && hlsdl)
/**
 * The driven window never takes the user's foreground (heaps-drive spec §1): shown without
 * activation, a utility (tool) window — never in the taskbar or Alt+Tab — and created 200 px past
 * the right edge of every display, so it is never on a display at all. DRIVE_VISIBLE=1 keeps it on
 * screen. Call before the app creates its window. From Simplified's Main (its automation hook).
 *
 * An uncaught error never opens heaps' "Uncaught Exception" window either (hxd.System.reportError:
 * a blocking hl.UI.WinLog on the user's screen, which stops the main loop until someone clicks it,
 * so a client sees only its own timeout). Off-screen, the error and its stack go to stderr and the
 * process exits with code 70; the socket closes with it.
 */
class OffScreen {
	/** The exit code of an app that died of an uncaught error (EX_SOFTWARE). */
	public static inline var CRASH_EXIT_CODE = 70;

	public static function install():Void {
		// The first hint is SDL2's name; SDL3 (3.4) uses the other two: shown without activating,
		// and hlsdl's SDL_RaiseWindow after creating it without either.
		sdl.Sdl.setHint("SDL_WINDOW_NO_ACTIVATION_WHEN_SHOWN", "1");
		sdl.Sdl.setHint("SDL_WINDOW_ACTIVATE_WHEN_SHOWN", "0");
		sdl.Sdl.setHint("SDL_WINDOW_ACTIVATE_WHEN_RAISED", "0");
		var create = hxd.System.createWindow;
		var visible = Sys.getEnv("DRIVE_VISIBLE") == "1";
		if (!visible) hxd.System.reportError = crash;
		hxd.System.createWindow = () -> {
			var at = visible ? null : position();
			hxd.Window.initialPosition = at;
			hxd.Window.initialFlags = sdl.Window.SDL_WINDOW_UTILITY;
			var w = create();
			hxd.Window.initialPosition = null;
			hxd.Window.initialFlags = 0;
			if (at != null) {
				if (w.x != at.x || w.y != at.y) w.setPosition(at.x, at.y);   // SDL moved it: put it back
				Sys.println('DRIVE: window created off-screen at ${w.x},${w.y}');
			}
			return w;
		};
	}

	/** heaps' reportError without its window: the same text (the error, then its stack) to stderr,
	    flushed, then exit. */
	static function crash(e:Dynamic):Void {
		var exc = Std.downcast(e, haxe.Exception);
		var stack = try haxe.CallStack.toString(exc != null ? exc.stack : haxe.CallStack.exceptionStack(true)) catch (_:Dynamic) "";
		var err = try Std.string(e) catch (_:Dynamic) "????";
		try {
			Sys.stderr().writeString(err + stack + "\r\n");
			Sys.stderr().flush();
		} catch (_:Dynamic) {}
		Sys.exit(CRASH_EXIT_CODE);
	}

	/** 200 px past the right edge of every display. hl.exe is per-monitor DPI aware, so SDL's display
	    bounds and window positions are both physical pixels. */
	static function position():{x:Int, y:Int} {
		var right:Null<Int> = null, top:Null<Int> = null;
		for (d in sdl.Sdl.getDisplays()) {
			if (right == null || d.right > right) right = d.right;
			if (top == null || d.top < top) top = d.top;
		}
		return {x: (right == null ? 0 : right) + 200, y: top == null ? 0 : top};
	}
}
#end
