package drive.haxeui;

#if haxeui_core
import drive.Node;
import drive.Viewport;
import haxe.ui.Toolkit;
import haxe.ui.core.Component;
import haxe.ui.core.Screen;

private enum Lookup {
	One(c:Component);
	None(why:String);
	Several(c:Array<Node>);
	NotMine;
}

/**
 * Finds HaxeUI components (heaps-drive spec §1 Finders) — Simplified's rca.client.automation.Targets,
 * behaviour unchanged, reporting window pixels through the scene's viewport. `#id`, `text:Exact`,
 * `text~:part` (any case), `{target, within}`. Hidden subtrees and a dataSource box's item-renderer
 * template are skipped unless includeHidden; a Button's own inner Label collapses into it; a
 * password field's text never leaves the app. Occlusion is not checked (HaxeUI has no hit test the
 * channel can ask); `disabled` is.
 */
class Targets implements drive.ITargets {
	static inline var MAX_CANDIDATES = 20;

	var scene:h2d.Scene;

	public function new(scene:h2d.Scene) this.scene = scene;

	public function resolve(spec:Dynamic, includeHidden:Bool):Resolved {
		return switch (lookup(spec, includeHidden)) {
			case One(c): Found(hit(c));
			case None(why): Missing(why);
			case Several(c): Many(c);
			case NotMine: Unknown;
		};
	}

	public function tree(within:Dynamic, includeHidden:Bool):Null<Array<Node>> {
		if (within == null) return [for (c in Screen.instance.rootComponents) if (includeHidden || !out(c)) node(c, true, includeHidden)];
		return switch (lookup(within, includeHidden)) {
			case One(c): [node(c, true, includeHidden)];
			case _: null;
		};
	}

	/** The id, or the type, of the component with the focus; null when none has it. */
	public static function focused():Null<String> {
		var f = haxe.ui.focus.FocusManager.instance.focus;
		if (f == null) return null;
		var c:Component = cast f;
		return c.id != null && c.id != "" ? c.id : typeOf(c);
	}

	function lookup(spec:Dynamic, includeHidden:Bool):Lookup {
		var scope:Null<Component> = null;
		var target:Dynamic = spec;
		if (spec != null && !Std.isOfType(spec, String) && Reflect.isObject(spec)) {
			target = spec.target;
			if (spec.within != null) switch (lookup(spec.within, includeHidden)) {
				case One(c): scope = c;
				case None(why): return None("within: " + why);
				// The scope itself is ambiguous: the candidates are scopes, each marked ambiguousScope.
				case Several(c): for (n in c) n.ambiguousScope = true; return Several(c);
				case NotMine: return NotMine;
			}
		}
		if (!Std.isOfType(target, String)) return NotMine;
		var test = matcher(target);
		if (test == null) return NotMine;
		var found:Array<Component> = [];
		walk(scope == null ? Screen.instance.rootComponents : scope.childComponents, includeHidden, test, found, null);
		return switch (found.length) {
			case 0: None("no component matches " + target);
			case 1: One(found[0]);
			case _: Several([for (c in found.slice(0, MAX_CANDIDATES)) node(c, false, includeHidden)]);
		};
	}

	function hit(c:Component):Hit {
		var m = Viewport.toWindow(scene, (c.screenLeft + c.width / 2) * Toolkit.scaleX, (c.screenTop + c.height / 2) * Toolkit.scaleY);
		return {node: node(c, false, false), cx: m.x, cy: m.y, occluder: () -> null, text: () -> ownText(c)};
	}

	public function node(c:Component, withChildren:Bool, includeHidden:Bool):Node {
		var focus = haxe.ui.focus.FocusManager.instance.focus;
		var p0 = Viewport.toWindow(scene, c.screenLeft * Toolkit.scaleX, c.screenTop * Toolkit.scaleY);
		var p1 = Viewport.toWindow(scene, (c.screenLeft + c.width) * Toolkit.scaleX, (c.screenTop + c.height) * Toolkit.scaleY);
		var n:Node = {
			source: "haxeui", type: typeOf(c), id: c.id == null ? "" : c.id, text: ownText(c),
			x: Math.round(p0.x), y: Math.round(p0.y), w: Math.round(p1.x - p0.x), h: Math.round(p1.y - p0.y),
			disabled: c.disabled, focused: focus != null && (cast focus : Component) == c
		};
		if (isPassword(c)) n.passwordLength = rawText(c).length;
		if (withChildren) n.children = [for (k in c.childComponents) if (includeHidden || !out(k)) node(k, true, includeHidden)];
		return n;
	}

	static function typeOf(c:Component):String return Type.getClassName(Type.getClass(c)).split(".").pop();

	/** Hidden, or the <item-renderer> a dataSource box keeps as its rows' template: HaxeUI hides that
	    one without setting `hidden`, so it would be a second, empty match for every row's ids. */
	static function out(c:Component):Bool {
		if (c.hidden) return true;
		var box = Std.downcast(c.parentComponent, haxe.ui.containers.Box);
		return box != null && box.itemRenderer == c;
	}

	static function matcher(t:String):Null<Component->Bool> {
		if (StringTools.startsWith(t, "#")) { var id = t.substr(1); return c -> c.id == id; }
		if (StringTools.startsWith(t, "text~:")) { var s = t.substr(6).toLowerCase(); return c -> ownText(c).toLowerCase().indexOf(s) >= 0; }
		if (StringTools.startsWith(t, "text:")) { var s = t.substr(5); return c -> ownText(c) == s; }
		return null;
	}

	static function isPassword(c:Component):Bool
		return Std.isOfType(c, haxe.ui.components.TextField) && (cast c : haxe.ui.components.TextField).password;

	/** What text targets match and nodes report. A password field has none. */
	static function ownText(c:Component):String return isPassword(c) ? "" : rawText(c);

	static function rawText(c:Component):String {
		var t:Null<String> = try c.text catch (_:Dynamic) null;
		return t == null ? "" : t;
	}

	/** Collects every match under `list`. The one thing collapsed: a matched Label whose text equals
	    that of an already-matched ancestor — the inner label HaxeUI puts inside a Button or CheckBox.
	    Every other match stays, so a container and a child sharing text are ambiguous. */
	static function walk(list:Array<Component>, includeHidden:Bool, test:Component->Bool, found:Array<Component>, ancestorText:Null<String>):Void {
		for (c in list) {
			if (!includeHidden && out(c)) continue;
			var below = ancestorText;
			if (test(c)) {
				if (!(Std.isOfType(c, haxe.ui.components.Label) && ancestorText != null && ownText(c) == ancestorText)) {
					found.push(c);
					below = ownText(c);
				}
			}
			walk(c.childComponents, includeHidden, test, found, below);
		}
	}
}
#end
