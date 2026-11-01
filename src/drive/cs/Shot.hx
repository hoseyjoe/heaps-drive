package drive.cs;

#if (haxeui_cs && haxeui_cs_drive)
import haxe.ui.backend.cs.native.Native.AppDriver;

/** A screenshot of the window's client area (AppDriver.CapturePng: rendered, so it works with the
    window off every display), at 96 dpi: one image pixel is one window unit, whatever the display's
    scale or Toolkit.scale. A crop arrives in window units. */
class Shot implements drive.IShot {
	public function new() {}

	public function capture(crop:Null<{x:Float, y:Float, w:Float, h:Float}>):Null<{png:haxe.io.Bytes, w:Int, h:Int}> {
		var data;
		if (crop == null) data = AppDriver.CapturePng(0, 0, 0, 0);
		else {
			var w = Math.round(crop.w), h = Math.round(crop.h);
			// AppDriver takes a width of 0 or less as the whole client area: a crop with no width is no crop at all.
			if (w < 1 || h < 1) return null;
			data = AppDriver.CapturePng(Math.round(crop.x), Math.round(crop.y), w, h);
		}
		if (data == null) return null;
		var png = haxe.io.Bytes.ofData(data);
		return {png: png, w: bigEndian(png, 16), h: bigEndian(png, 20)};
	}

	/** The PNG's IHDR holds its size: width at byte 16, height at byte 20, both big-endian. */
	static function bigEndian(png:haxe.io.Bytes, at:Int):Int
		return (png.get(at) << 24) | (png.get(at + 1) << 16) | (png.get(at + 2) << 8) | png.get(at + 3);
}
#end
