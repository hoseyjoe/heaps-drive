package drive.cs;

#if (haxeui_cs && haxeui_cs_drive)
import haxe.ui.backend.cs.Callbacks;
import haxe.ui.backend.cs.native.Native.AppDriver;
import haxe.ui.backend.cs.native.Native.FileDialogs;

/**
 * Opens the drive channel for a HaxeUI app on C# (heaps-drive spec §1), headless or in a real
 * window. Call `start` once the UI is ready; under `-D haxeui_cs_headless` follow it with
 * `runHeadless`, which is what runs the app there.
 */
class Channel {
	/** Opens the channel over AppDriver's input and capture; it closes with the window, or on `quit`.
	    Finders are tried together (drive.Finder): list the app's own after the built-in ones. */
	public static function start(host:Null<IDriveHost>, finders:Array<ITargets>, dir:String):Void {
		var cleanup = Start.open(host, finders, new Input(), new Shot(), new CsWindow(), dir);
		AppDriver.OnClosed(Callbacks.callback(cleanup));
	}

	/** The `filePicker` command: every picker from now on answers with these paths at once (none:
	    Cancel), where a driven build would otherwise refuse. No picker opens, so its code does not run:
	    this tests what the app does with an answer, not the picker. */
	public static function answerFilePickers(paths:Array<String>):Void {
		var native = new cs.NativeArray<String>(paths.length);
		for (i in 0...paths.length) native[i] = paths[i];
		FileDialogs.TestResponse = native;
	}

	#if haxeui_cs_headless
	/** There is no window to run the app, so this does: Haxe's events, HaxeUI's validation and a render
	    sixty times a second in real time. Never returns; the app ends it with Host.Exit. */
	public static function runHeadless():Void {
		while (true) {
			haxe.ui.backend.cs.TestDriver.pump(1);
			Sys.sleep(1 / 60);
		}
	}
	#end
}
#end
