package drive.heaps;

/** The heaps window, for `resize`. */
class HeapsWindow implements drive.IWindow {
	var window:hxd.Window;
	public function new(window:hxd.Window) this.window = window;
	public function resize(w:Int, h:Int):Void window.resize(w, h);
	public function size():{w:Int, h:Int} return {w: window.width, h: window.height};
}
