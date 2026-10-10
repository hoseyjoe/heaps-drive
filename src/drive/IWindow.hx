package drive;

/** The app's window, for `resize` (heaps-drive spec §1). Sizes are window pixels. */
interface IWindow {
	function resize(w:Int, h:Int):Void;
	function size():{w:Int, h:Int};
}
