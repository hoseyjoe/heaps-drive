package drive;

/** Synthetic input at WINDOW pixels (heaps-drive spec §1, the backend seam). */
interface IInput {
	function move(x:Float, y:Float):Void;
	function push(x:Float, y:Float, button:Int):Void;
	function release(x:Float, y:Float, button:Int):Void;
	function click(x:Float, y:Float, button:Int, double:Bool):Void;
	function wheel(x:Float, y:Float, notches:Int):Void;
	function keyDown(code:Int):Void;
	function keyUp(code:Int):Void;
	function text(charCode:Int):Void;
	/** Lets go of every key and button still held. */
	function releaseHeld():Void;
	/** The key code for one part of a key name ("Enter", "A", "-"), or null. */
	function keyCode(part:String):Null<Int>;
	/** Whether these keys together are copy, cut or paste, which the channel never sends. */
	function touchesClipboard(codes:Array<Int>):Bool;
}
