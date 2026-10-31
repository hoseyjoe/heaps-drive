import drive.Start;
import utest.Assert;
import Fakes;

class StartTest extends utest.Test {
	function testOpenWritesAndCleansUp() {
		// test.hxml has no -lib heaps: that this compiles at all is the proof Start no longer needs it.
		var dir = "bin/start-test-" + Std.string(Std.random(0x7FFFFFFF));
		sys.FileSystem.createDirectory(dir);
		var file = dir + "/drive.json";
		var cleanup = Start.open(null, [new FakeTargets()], new FakeInput(), null, null, dir);
		var written = haxe.Json.parse(sys.io.File.getContent(file));
		Assert.isTrue(written.port > 0);
		Assert.equals(32, (written.token : String).length);
		cleanup();
		Assert.isFalse(sys.FileSystem.exists(file));
		cleanup();   // a second call is harmless
		sys.FileSystem.deleteDirectory(dir);
	}
}
