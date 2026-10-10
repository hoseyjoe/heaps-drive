import utest.Runner;
import utest.ui.Report;

class TestAll {
	public static function main() {
		var runner = new Runner();
		runner.addCase(new SessionTest());
		runner.addCase(new ServerTest());
		runner.addCase(new FinderTest());
		runner.addCase(new CommandsTest());
		// Before Report: its completion handler exits the process, non-zero on any failure.
		Report.create(runner);
		runner.run();
	}
}
