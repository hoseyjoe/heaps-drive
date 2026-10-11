package drive.macro;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

/**
 * Lets the driven build create its window where it asks, instead of centred on the primary
 * display (heaps-drive spec §1). hxd.Window's constructor always passes
 * SDL_WINDOWPOS_CENTERED, and SDL shows the window as it creates it, so moving it afterwards leaves
 * it on screen while the GL context is made (about 160 ms here). This adds
 * `hxd.Window.initialPosition` and makes the constructor use it when it is set. It also adds
 * `hxd.Window.initialFlags`, SDL window flags or-ed into the constructor's own: the automation build
 * passes SDL_WINDOW_UTILITY, so its window is a tool window (WS_EX_TOOLWINDOW on Windows) that never
 * shows in the taskbar or Alt+Tab, from creation, before its first paint. Added to hxd.Window by
 * extraParams.hxml, only when -D drive and hlsdl are both defined.
 */
class WindowPosition {
    /** extraParams.hxml's hook: every build naming -lib heaps-drive runs it, and it does nothing
        unless the build is a driven one on SDL. */
    public static function register():Void {
        if (Context.defined("drive") && Context.defined("hlsdl"))
            haxe.macro.Compiler.addMetadata("@:build(drive.macro.WindowPosition.allowInitialPosition())", "hxd.Window");
    }

    public static function allowInitialPosition():Array<Field> {
        var fields = Context.getBuildFields();
        var replaced = false;
        function rewrite(e:Expr):Expr {
            return switch (e.expr) {
                case ENew({pack: ["sdl"], name: "Window"}, args) if (args.length == 6):
                    replaced = true;
                    var x = args[3], y = args[4], flags = args[5];
                    args = args.copy();
                    args[3] = macro (initialPosition == null ? $x : initialPosition.x);
                    args[4] = macro (initialPosition == null ? $y : initialPosition.y);
                    args[5] = macro ($flags | initialFlags);
                    {expr: ENew({pack: ["sdl"], name: "Window"}, args), pos: e.pos};
                case _: haxe.macro.ExprTools.map(e, rewrite);
            };
        }
        for (f in fields) if (f.name == "new") switch (f.kind) {
            case FFun(fn) if (fn.expr != null): fn.expr = rewrite(fn.expr);
            case _:
        }
        if (!replaced)
            Context.warning("hxd.Window creates no sdl.Window the way WindowPosition expects; the automation window will show centred before it is parked", Context.currentPos());
        fields.push({
            name: "initialPosition",
            access: [APublic, AStatic],
            kind: FVar(macro :Null<{x:Int, y:Int}>, macro null),
            pos: Context.currentPos(),
            doc: "Where the next window is created (automation build only); null: centred."
        });
        fields.push({
            name: "initialFlags",
            access: [APublic, AStatic],
            kind: FVar(macro :Int, macro 0),
            pos: Context.currentPos(),
            doc: "SDL window flags added to the next window's (automation build only)."
        });
        return fields;
    }
}
#end
