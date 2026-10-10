package drive;

/** How a client reaches the command table (heaps-drive spec §1, the backend seam). HashLink desktop:
    `Server`, TCP on 127.0.0.1. A browser build would be a `window.drive()` bridge instead. */
interface ITransport {
	/** Called once a frame, on the UI thread. */
	function tick():Void;
	function close():Void;
	var connected(get, never):Bool;
	/** Called whenever a client goes, so held input can be let go. */
	var onClientGone:Void->Void;
	/** Called when a deferred request times out, for the same reason. */
	var onTimeout:Void->Void;
}
