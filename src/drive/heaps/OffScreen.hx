package drive.heaps;

#if (drive && hlsdl)
/**
 * The driven window never takes the user's foreground (heaps-drive spec §1): shown without
 * activation, a utility (tool) window — never in the taskbar or Alt+Tab — and created 200 px past
 * the right edge of every display, so it is never on a display at all. DRIVE_VISIBLE=1 keeps it on
 * screen. Call before the app creates its window. From Simplified's Main (its automation hook).
 */
class OffScreen {
	public static function install():Void {
		// The first hint is SDL2's name; SDL3 (3.4) uses the other two: shown without activating,
		// and hlsdl's SDL_RaiseWindow after creating it without either.
		sdl.Sdl.setHint("SDL_WINDOW_NO_ACTIVATION_WHEN_SHOWN", "1");
		sdl.Sdl.setHint("SDL_WINDOW_ACTIVATE_WHEN_SHOWN", "0");
		sdl.Sdl.setHint("SDL_WINDOW_ACTIVATE_WHEN_RAISED", "0");
		var create = hxd.System.createWindow;
		var visible = Sys.getEnv("DRIVE_VISIBLE") == "1";
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
