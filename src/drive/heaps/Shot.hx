package drive.heaps;

import drive.Viewport;

/** A screenshot of the scene, rendered to a texture — which works with the window off-screen. Its
    size is the scene's own: under a LetterBox, the design canvas, not the window. A crop arrives in
    window pixels and is mapped back to scene units. */
class Shot implements drive.IShot {
	var scene:h2d.Scene;

	public function new(scene:h2d.Scene) this.scene = scene;

	public function pixels(crop:Null<{x:Float, y:Float, w:Float, h:Float}>):Null<hxd.Pixels> {
		var bmp = scene.captureBitmap();
		var tex = bmp.tile.getTexture();
		// captureBitmap allocates a render target per call (the bitmap was never added to the
		// scene): it is disposed whether or not reading it back works.
		var px = try tex.capturePixels() catch (e:Dynamic) { tex.dispose(); throw e; }
		tex.dispose();
		if (crop == null) return px;
		var a = Viewport.toScene(scene, crop.x, crop.y);
		var b = Viewport.toScene(scene, crop.x + crop.w, crop.y + crop.h);
		var x0 = Std.int(Math.max(0, a.x)), y0 = Std.int(Math.max(0, a.y));
		var x1 = Std.int(Math.min(px.width, b.x)), y1 = Std.int(Math.min(px.height, b.y));
		if (x1 <= x0 || y1 <= y0) return null;
		return px.sub(x0, y0, x1 - x0, y1 - y0);
	}

	public function capture(crop:Null<{x:Float, y:Float, w:Float, h:Float}>):Null<{png:haxe.io.Bytes, w:Int, h:Int}> {
		var px = pixels(crop);
		return px == null ? null : {png: px.toPNG(), w: px.width, h: px.height};
	}
}
