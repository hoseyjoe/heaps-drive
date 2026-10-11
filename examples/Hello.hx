/** The smallest driven app: one h2d button on a letterboxed canvas, counting its clicks. The lib's
    selftest (tools/selftest.mjs) launches it off-screen and drives it. */
class Hello extends hxd.App implements drive.IDriveHost {
	var clicks = 0;
	var count:h2d.Text;

	static function main() {
		drive.heaps.OffScreen.install();
		new Hello();
	}

	override function init() {
		s2d.scaleMode = LetterBox(200, 100);
		var font = hxd.res.DefaultFont.get();
		var g = new h2d.Graphics(s2d);
		g.beginFill(0x336699); g.drawRect(20, 20, 80, 30); g.endFill();
		var t = new h2d.Text(font, s2d);
		t.text = "Hello"; t.textAlign = Center; t.x = 60; t.y = 28;
		var i = new h2d.Interactive(80, 30, s2d);
		i.x = 20; i.y = 20;
		i.onClick = _ -> { clicks++; count.text = "clicked " + clicks; };
		count = new h2d.Text(font, s2d);
		count.name = "count"; count.text = "clicked 0"; count.x = 120; count.y = 28;
		var dir = Sys.getEnv("DRIVE_DIR");
		drive.Start.start(this, [new drive.h2d.Targets(s2d)], s2d, hxd.Window.getInstance(), dir == null ? "." : dir);
	}

	public function condition(cond:Dynamic):Null<{check:Void->Bool, seen:Void->Dynamic}>
		return cond.clicks != null ? {check: () -> clicks >= cond.clicks, seen: () -> (clicks : Dynamic)} : null;
	public function state(args:Dynamic):Dynamic return {clicks: clicks};
	public function quit() hxd.System.exit();
}
