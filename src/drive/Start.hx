package drive;

#if sys
/**
 * Opens the channel (heaps-drive spec §1): a token, the loopback server, the `drive.json` that tells
 * a client where it is, a per-frame tick, and cleanup on quit or window close. Call once the scene
 * exists. Finders are tried together (drive.Finder): list the app's own after the built-in ones.
 * `open` takes the backend's three seams and names no toolkit; `start` is the Heaps one.
 */
class Start {
	#if heaps
	public static function start(host:Null<IDriveHost>, finders:Array<ITargets>, scene:h2d.Scene, window:hxd.Window, dir:String):Void {
		var cleanup = open(host, finders, new drive.heaps.Input(window), new drive.heaps.Shot(scene),
			new drive.heaps.HeapsWindow(window), dir);
		var previous = window.onClose;
		window.onClose = () -> { var closing = previous(); if (closing) cleanup(); return closing; };
	}
	#end

	/** Opens the channel over the given backend; answers the function that closes it again (a second
	    call does nothing). The `quit` command calls it too. */
	public static function open(host:Null<IDriveHost>, finders:Array<ITargets>, input:IInput, shot:Null<IShot>, window:Null<IWindow>,
			dir:String):Void->Void {
		var token = newToken();
		var commands = new Commands(new Finder(finders), input, shot, window, host, haxe.Timer.stamp);
		#if (haxeui_core || haxeui_cs)
		// `key` answers what has the focus when HaxeUI is a finder: HaxeUI is what knows.
		for (f in finders) if (Std.isOfType(f, drive.haxeui.Targets)) commands.focused = drive.haxeui.Targets.focused;
		#end
		var server = new Server(token, commands.dispatch, haxe.Timer.stamp);
		// A client that goes away, or a `key`/`drag` that times out, must not leave a key or button held.
		server.onClientGone = commands.releaseHeld;
		server.onTimeout = commands.releaseHeld;
		var file = haxe.io.Path.join([sys.FileSystem.absolutePath(dir), "drive.json"]);
		try sys.io.File.saveContent(file, haxe.Json.stringify({port: server.port, token: token}))
		catch (e:Dynamic) Sys.println("DRIVE: could not write " + file + ": " + Std.string(e));
		Sys.println("DRIVE BUILD: control channel on 127.0.0.1:" + server.port + " (" + file + ")");
		haxe.MainLoop.add(() -> try server.tick() catch (e:Dynamic) Sys.println("DRIVE: tick failed: " + Std.string(e)));
		var done = false;
		var cleanup = () -> if (!done) { done = true; server.close(); try sys.FileSystem.deleteFile(file) catch (_:Dynamic) {} };
		commands.onQuit = cleanup;
		return cleanup;
	}

	/** Guards a loopback port against an accidental or other-user client; anything able to abuse a
	    weak token can read drive.json anyway. */
	static function newToken():String {
		var seed = new StringBuf();
		for (_ in 0...8) seed.add(Std.random(0x7FFFFFFF));
		seed.add(Sys.time()); seed.add(haxe.Timer.stamp());
		return haxe.crypto.Sha256.encode(seed.toString()).substr(0, 32);
	}
}
#end
