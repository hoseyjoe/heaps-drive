package drive.h2d;

import drive.Node;
import drive.Viewport;
import h2d.Interactive;
import h2d.Object;

/**
 * Finds h2d things (heaps-drive spec §1 Finders).
 * - `name:foo` matches `Object.name`.
 * - `text:Label` / `text~:part` (any case) match a visible h2d.Text whose centre lies inside a
 *   visible SIBLING Interactive — UiButton's shape: a Text, a Graphics and an Interactive over one
 *   box, none of them named. When several siblings contain it (a full-screen scrim is a sibling
 *   too), the smallest is the button. A Text over no sibling Interactive is not a target: a label
 *   drawn beside its button would otherwise be a click on empty air.
 * - `{target, within: "name:..."}` searches under that one named object.
 * Visible means it and every parent are, and it is on this scene. Occlusion is the scene's own hit
 * test (Scene.getInteractive): an h2d Interactive drawn over the target. A HaxeUI component over it
 * is not seen.
 */
class Targets implements drive.ITargets {
	static inline var MAX_CANDIDATES = 20;

	var scene:h2d.Scene;

	public function new(scene:h2d.Scene) this.scene = scene;

	public function resolve(spec:Dynamic, includeHidden:Bool):Resolved {
		var target:Dynamic = spec;
		var scope:Object = scene;
		if (spec != null && !Std.isOfType(spec, String) && Reflect.isObject(spec)) {
			target = spec.target;
			if (spec.within != null) {
				if (!Std.isOfType(spec.within, String) || !StringTools.startsWith(spec.within, "name:")) return Unknown;
				var named = collectNamed(scene, spec.within.substr(5), includeHidden);
				if (named.length == 0) return Missing("within: no h2d object is named " + spec.within.substr(5));
				if (named.length > 1) {
					var c = [for (o in named.slice(0, MAX_CANDIDATES)) node(o)];
					for (n in c) n.ambiguousScope = true;
					return Many(c);
				}
				scope = named[0];
			}
		}
		if (!Std.isOfType(target, String)) return Unknown;
		var t:String = target;
		var found:Array<Object>;
		if (StringTools.startsWith(t, "name:")) found = collectNamed(scope, t.substr(5), includeHidden);
		else if (StringTools.startsWith(t, "text~:")) { var s = t.substr(6).toLowerCase(); found = buttons(scope, includeHidden, x -> x.toLowerCase().indexOf(s) >= 0); }
		else if (StringTools.startsWith(t, "text:")) { var s = t.substr(5); found = buttons(scope, includeHidden, x -> x == s); }
		else return Unknown;
		return switch (found.length) {
			case 0: Missing("no h2d object matches " + t);
			case 1: Found(hit(found[0]));
			case _: Many([for (o in found.slice(0, MAX_CANDIDATES)) node(o)]);
		};
	}

	/** A flat list of what can be targeted: every visible Interactive (with its label) and every
	    named object — the whole h2d tree would be thousands of Graphics. */
	public function tree(within:Dynamic, includeHidden:Bool):Null<Array<Node>> {
		var scope:Object = scene;
		if (within != null) {
			if (!Std.isOfType(within, String) || !StringTools.startsWith(within, "name:")) return null;
			var named = collectNamed(scene, within.substr(5), includeHidden);
			if (named.length != 1) return null;
			scope = named[0];
		}
		var out:Array<Node> = [];
		walk(scope, includeHidden, o -> if (Std.isOfType(o, Interactive) || (o.name != null && o.name != "")) out.push(node(o)));
		return out;
	}

	function walk(o:Object, includeHidden:Bool, visit:Object->Void):Void {
		for (c in o) {
			if (!includeHidden && !c.visible) continue;
			visit(c);
			walk(c, includeHidden, visit);
		}
	}

	function collectNamed(scope:Object, name:String, includeHidden:Bool):Array<Object> {
		var out = [];
		walk(scope, includeHidden, o -> if (o.name == name) out.push(o));
		return out;
	}

	/** The Interactive each matching label sits on, once each. */
	function buttons(scope:Object, includeHidden:Bool, test:String->Bool):Array<Object> {
		var out:Array<Object> = [];
		walk(scope, includeHidden, o -> {
			var t = Std.downcast(o, h2d.Text);
			if (t == null || !test(t.text)) return;
			var b = buttonUnder(t, includeHidden);
			if (b != null && out.indexOf(b) < 0) out.push(b);
		});
		return out;
	}

	function buttonUnder(t:h2d.Text, includeHidden:Bool):Null<Interactive> {
		if (t.parent == null) return null;
		var tb = t.getBounds();
		var cx = (tb.xMin + tb.xMax) / 2, cy = (tb.yMin + tb.yMax) / 2;
		var best:Null<Interactive> = null, bestArea = Math.POSITIVE_INFINITY;
		for (s in t.parent) {
			var i = Std.downcast(s, Interactive);
			if (i == null || (!includeHidden && !i.visible)) continue;
			var b = boundsOf(i);
			if (cx < b.xMin || cx > b.xMax || cy < b.yMin || cy > b.yMax) continue;
			var area = (b.xMax - b.xMin) * (b.yMax - b.yMin);
			if (area < bestArea) { best = i; bestArea = area; }
		}
		return best;
	}

	/** The bounds of `o` in scene units. An Interactive contributes nothing to `getBounds` (it only
	    counts when it paints a background), so its own box is carried through `localToGlobal` — which
	    also turns a rotated container's box into the axis-aligned box around it. */
	function boundsOf(o:Object):h2d.col.Bounds {
		var i = Std.downcast(o, Interactive);
		if (i == null) return o.getBounds();
		var b = new h2d.col.Bounds();
		for (c in [[0., 0.], [i.width, 0.], [0., i.height], [i.width, i.height]]) {
			var p = i.localToGlobal(new h2d.col.Point(c[0], c[1]));
			b.addPos(p.x, p.y);
		}
		return b;
	}

	/** The text of the label on `o`: its own if it is a Text, else a sibling Text centred inside it. */
	function labelOf(o:Object):String {
		var t = Std.downcast(o, h2d.Text);
		if (t != null) return t.text;
		if (o.parent == null) return "";
		var b = boundsOf(o);
		for (s in o.parent) {
			var st = Std.downcast(s, h2d.Text);
			if (st == null || !st.visible) continue;
			var sb = st.getBounds();
			var cx = (sb.xMin + sb.xMax) / 2, cy = (sb.yMin + sb.yMax) / 2;
			if (cx >= b.xMin && cx <= b.xMax && cy >= b.yMin && cy <= b.yMax) return st.text;
		}
		return "";
	}

	function typeOf(o:Object):String return Type.getClassName(Type.getClass(o)).split(".").pop();

	function describe(o:Object):String {
		var label = labelOf(o);
		return typeOf(o) + (o.name != null && o.name != "" ? " '" + o.name + "'" : "")
			+ (label != "" ? " labelled '" + label + "'" : "") + " in " + path(o);
	}

	function path(o:Object):String {
		var parts = [], p = o.parent;
		while (p != null && p != scene && parts.length < 4) {
			parts.unshift(p.name != null && p.name != "" ? p.name : typeOf(p));
			p = p.parent;
		}
		return parts.length == 0 ? "the scene" : parts.join(" > ");
	}

	function node(o:Object):Node {
		var b = boundsOf(o);
		var p0 = Viewport.toWindow(scene, b.xMin, b.yMin), p1 = Viewport.toWindow(scene, b.xMax, b.yMax);
		return {
			source: "h2d", type: typeOf(o), id: o.name == null ? "" : o.name, text: labelOf(o),
			x: Math.round(p0.x), y: Math.round(p0.y), w: Math.round(p1.x - p0.x), h: Math.round(p1.y - p0.y),
			disabled: false, focused: false, path: path(o)
		};
	}

	function hit(o:Object):Hit {
		var b = boundsOf(o);
		var sx = (b.xMin + b.xMax) / 2, sy = (b.yMin + b.yMax) / 2;
		var c = Viewport.toWindow(scene, sx, sy);
		return {node: node(o), cx: c.x, cy: c.y, occluder: () -> occluder(o, sx, sy), text: () -> labelOf(o)};
	}

	/** What the scene's own hit test finds at the target's centre, when that is not the target (or
	    something inside it). */
	function occluder(o:Object, sx:Float, sy:Float):Null<String> {
		var top = scene.getInteractive(sx, sy);
		if (top == null) return null;
		var p:Object = top;
		while (p != null) { if (p == o) return null; p = p.parent; }
		return describe(top);
	}
}
