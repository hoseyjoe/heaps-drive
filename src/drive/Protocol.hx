package drive;

/** One request off the wire (heaps-drive spec §1). */
typedef Request = { id:Int, cmd:String, args:Dynamic };

/** What a command produced. `Later` is polled once a frame until it gives an outcome or its deadline
    passes, which answers `timeout` with `lastSeen()`. `Failed`'s detail goes out as `candidates`. */
enum Outcome {
	Done(result:Dynamic);
	Failed(code:String, error:String, ?detail:Dynamic);
	Later(poll:Void->Null<Outcome>, deadline:Float, lastSeen:Void->Dynamic);
}

/** One client's byte stream. */
interface IConnection {
	/** Text received since the last call ("" when none); null once the client has gone. */
	function receive():Null<String>;
	function send(text:String):Void;
	function close():Void;
}
