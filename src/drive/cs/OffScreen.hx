package drive.cs;

#if (haxeui_cs && haxeui_cs_drive)
import haxe.ui.backend.cs.native.Native.AppDriver;

/**
 * The driven window never takes the user's foreground (heaps-drive spec §1). haxeui-cs puts it
 * past the right edge of every display, shown without activation, out of the taskbar and Alt+Tab,
 * with the platform styles that keep a click on it from activating it; this asks for that. Headless
 * there is no window and this does nothing. DRIVE_VISIBLE=1 puts the window on a display for a
 * human to watch. It still gets the non-activating, tool-window styles every driven window gets
 * (haxeui-cs's AppDriver.ApplyWindow), which should keep it from taking focus; but that mode has
 * NEVER BEEN RUN (it would put a window on a display), so "takes no focus" there is read from the code,
 * not shown by a run. Call before `new HaxeUIApp`.
 *
 * Unlike HashLink, nothing opens a blocking error window here: an error nobody catches ends the
 * process with a non-zero code and its message on stderr, and the socket closes with it.
 */
class OffScreen {
	public static function install():Void {
		#if !haxeui_cs_headless
		AppDriver.SetWindow(Sys.getEnv("DRIVE_VISIBLE") != "1");
		#end
	}
}
#end
