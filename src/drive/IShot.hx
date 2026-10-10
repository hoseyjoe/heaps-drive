package drive;

/** A screenshot as PNG (heaps-drive spec §1, the backend seam). `crop` is in WINDOW pixels; null
    when no part of it is inside the image. The image's own size is the backend's to choose (heaps:
    the scene's, which under a letterbox is the design canvas). */
interface IShot {
	function capture(crop:Null<{x:Float, y:Float, w:Float, h:Float}>):Null<{png:haxe.io.Bytes, w:Int, h:Int}>;
}
