package drive;

import drive.Node;

/** A finder (heaps-drive spec §1 Finders): turns a target string, or {target, within}, into a hit
    in window pixels. A target it does not recognise is `Unknown`, never `Missing`. */
interface ITargets {
	function resolve(spec:Dynamic, includeHidden:Bool):Resolved;
	/** What is under `within` (null: everything this finder sees), or null when `within` is not
	    this finder's or matches nothing. */
	function tree(within:Dynamic, includeHidden:Bool):Null<Array<Node>>;
}
