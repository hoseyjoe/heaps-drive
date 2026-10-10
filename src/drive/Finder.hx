package drive;

import drive.Node;

/**
 * Asks every finder and combines the answers (heaps-drive spec §1 Finders). Exactly one hit across
 * all of them is Found; more than one — in one finder or across several, e.g. a HaxeUI "Back" and an
 * h2d "Back" on screen together — is Many, never the first finder's pick. A target no finder
 * recognises is Missing, naming the forms there are.
 */
class Finder {
	public static inline var MAX_CANDIDATES = 20;

	var finders:Array<ITargets>;

	public function new(finders:Array<ITargets>) this.finders = finders;

	public function resolve(spec:Dynamic, includeHidden:Bool):Resolved {
		var found:Array<Hit> = [], many:Array<Node> = [], whys:Array<String> = [];
		var known = false;
		for (f in finders) switch (f.resolve(spec, includeHidden)) {
			case Found(h): known = true; found.push(h);
			case Many(c): known = true; for (n in c) many.push(n);
			case Missing(why): known = true; whys.push(why);
			case Unknown:
		}
		if (!known) return Missing("no finder takes " + haxe.Json.stringify(spec)
			+ ": a target is #id, text:Exact, text~:part, name:objectName or one of the app's prefixes");
		if (found.length == 1 && many.length == 0) return Found(found[0]);
		if (found.length == 0 && many.length == 0) return Missing(whys.join("; "));
		var all = [for (h in found) h.node].concat(many);
		return Many(all.slice(0, MAX_CANDIDATES));
	}

	/** Whether at least one finder takes `spec` as its kind of target (answers anything but Unknown).
	    A malformed target is not "gone": it is a mistake, and a wait on it must say so. */
	public function recognises(spec:Dynamic):Bool {
		for (f in finders) if (!f.resolve(spec, false).match(Unknown)) return true;
		return false;
	}

	public function tree(within:Dynamic, includeHidden:Bool):Null<Array<Node>> {
		var all:Array<Node> = [], any = false;
		for (f in finders) {
			var t = f.tree(within, includeHidden);
			if (t != null) { any = true; all = all.concat(t); }
		}
		return any ? all : null;
	}
}
