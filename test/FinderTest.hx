import drive.Finder;
import drive.Node;
import utest.Assert;
import Fakes;

class FinderTest extends utest.Test {
	function testOneFinderFindingItIsFound() {
		var a = new FakeTargets(), b = new FakeTargets();
		a.table.set("text:Go", Found(FakeTargets.hit("go", 1, 2)));
		b.table.set("text:Go", Missing("no h2d Go"));
		switch (new Finder([a, b]).resolve("text:Go", false)) {
			case Found(h): Assert.equals("go", h.node.id);
			case other: Assert.fail("expected Found, got " + other);
		}
	}

	function testTheSameTextInTwoFindersIsAmbiguousNotFirstWins() {
		var haxeui = new FakeTargets(), h2d = new FakeTargets();
		haxeui.table.set("text:Back", Found(FakeTargets.hit("uiBack", 1, 2)));
		h2d.table.set("text:Back", Found(FakeTargets.hit("h2dBack", 3, 4)));
		switch (new Finder([haxeui, h2d]).resolve("text:Back", false)) {
			case Many(c): Assert.same(["uiBack", "h2dBack"], [for (n in c) n.id]);
			case other: Assert.fail("expected Many, got " + other);
		}
	}

	function testNoFinderTakingItIsMissingWithTheForms() {
		switch (new Finder([new FakeTargets()]).resolve("banana", false)) {
			case Missing(why): Assert.isTrue(why.indexOf("#id") >= 0 && why.indexOf("name:") >= 0, why);
			case other: Assert.fail("expected Missing, got " + other);
		}
	}

	function testEveryFinderMissingJoinsTheReasons() {
		var a = new FakeTargets(), b = new FakeTargets();
		a.table.set("text:X", Missing("not in haxeui"));
		b.table.set("text:X", Missing("not in h2d"));
		switch (new Finder([a, b]).resolve("text:X", false)) {
			case Missing(why): Assert.isTrue(why.indexOf("not in haxeui") >= 0 && why.indexOf("not in h2d") >= 0, why);
			case other: Assert.fail("expected Missing, got " + other);
		}
	}

	function testRecognisesIsFalseWhenEveryFinderIsUnknownAndTrueOnceOneAnswers() {
		var a = new FakeTargets(), b = new FakeTargets();
		var finder = new Finder([a, b]);
		Assert.isFalse(finder.recognises("banana"));
		b.table.set("banana", Missing("nothing called banana"));
		Assert.isTrue(finder.recognises("banana"));
	}

	function testCandidatesAreCappedAtTwenty() {
		var a = new FakeTargets();
		a.table.set("text:Row", Many([for (i in 0...30) FakeTargets.node("r" + i)]));
		switch (new Finder([a]).resolve("text:Row", false)) {
			case Many(c): Assert.equals(Finder.MAX_CANDIDATES, c.length);
			case other: Assert.fail("expected Many, got " + other);
		}
	}
}
