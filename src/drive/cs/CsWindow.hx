package drive.cs;

#if (haxeui_cs && haxeui_cs_drive)
import haxe.ui.backend.cs.native.Native.AppDriver;
import haxe.ui.backend.cs.native.Native.Host;

/** The app's window, for `resize`. AppDriver.Resize takes a client size and settles on it over up to
    a second (an open window ends up a few units smaller than asked, and it corrects for that). So
    `size()` is the client size as it stands, never the size asked for: `Commands.resize` polls it
    until it is the one asked for, and answers with it. */
class CsWindow implements drive.IWindow {
	public function new() {}

	public function resize(w:Int, h:Int):Void AppDriver.Resize(w, h);

	public function size():{w:Int, h:Int} return {w: Math.round(Host.ClientWidth), h: Math.round(Host.ClientHeight)};
}
#end
