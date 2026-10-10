package drive;

/** One thing on screen as the channel reports it. x/y/w/h are WINDOW pixels — what a click takes.
    `source` names the finder: "haxeui", "h2d", or an app's. `path` is the h2d parent chain. */
typedef Node = {
	source:String,
	type:String,
	id:String,
	text:String,
	x:Int, y:Int, w:Int, h:Int,
	disabled:Bool,
	focused:Bool,
	?children:Array<Node>,
	?ambiguousScope:Bool,
	?passwordLength:Int,
	?path:String
};

/** A resolved target: its node, its centre in window pixels, what is drawn on top of it at that
    centre (null: nothing — a finder that cannot tell answers null), and its live text. */
typedef Hit = {
	node:Node,
	cx:Float,
	cy:Float,
	occluder:Void->Null<String>,
	text:Void->String
};

enum Resolved {
	Found(h:Hit);
	Missing(why:String);
	Many(candidates:Array<Node>);
	/** Not this finder's kind of target: the next finder is asked. */
	Unknown;
}
