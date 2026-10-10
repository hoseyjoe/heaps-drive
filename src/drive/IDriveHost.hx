package drive;

/** What an app hands the channel beyond its finders (heaps-drive spec §1). */
interface IDriveHost {
	/** One of the app's own wait conditions (e.g. {idle: true}), or null when `cond` is not one of
	    its: `check` is polled once a frame, `seen` explains a timeout. */
	function condition(cond:Dynamic):Null<{check:Void->Bool, seen:Void->Dynamic}>;
	/** A JSON-able snapshot of the app; `args` are the `state` command's. */
	function state(args:Dynamic):Dynamic;
	/** Save what should be saved and exit. */
	function quit():Void;
}
