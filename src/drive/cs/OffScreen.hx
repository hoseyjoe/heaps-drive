package drive.cs;

#if (haxeui_cs && haxeui_cs_drive)
import haxe.ui.backend.cs.native.Native.AppDriver;

/**
 * The driven window never takes the user's foreground (heaps-drive spec §1). haxeui-cs puts it
 * past the right edge of every display, shown without activation, out of the taskbar and Alt+Tab,
 * with the platform styles that keep a click on it from activating it; this asks for that. Headless
 * there is no window and this does nothing. DRIVE_VISIBLE=1 puts the window on a display for a
 * human to watch: it still takes no focus. Call before `new HaxeUIApp`.
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
