package drive;

/**
 * Scene units <-> window pixels, the way heaps maps a press: the scene's viewport, which a LetterBox
 * scale mode makes a zoom plus a centring offset. The camera is synced first — until a frame renders
 * its matrix is stale and every point collapses to the origin (JoeClash's SceneFitTest found this).
 * Assumes the scene camera is untransformed (at 0,0, scale 1, no rotation), every heaps app's default.
 */
class Viewport {
	public static function sync(s:h2d.Scene):Void {
		s.camera.sync(null, true);
		if (s.interactiveCamera != null) s.interactiveCamera.sync(null, true);
	}

	public static function toWindow(s:h2d.Scene, x:Float, y:Float):{x:Float, y:Float} {
		sync(s);
		return @:privateAccess {x: x * s.viewportScaleX + s.offsetX, y: y * s.viewportScaleY + s.offsetY};
	}

	public static function toScene(s:h2d.Scene, wx:Float, wy:Float):{x:Float, y:Float} {
		sync(s);
		return @:privateAccess {x: (wx - s.offsetX) / s.viewportScaleX, y: (wy - s.offsetY) / s.viewportScaleY};
	}
}
