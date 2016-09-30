import XCTest

@testable import PerlTests
@testable import PerlCoroTests

var tests = [XCTestCaseEntry]()
tests += [testCase(EmbedTests.allTests)]
tests += [testCase(ConvertFromPerlTests.allTests)]
tests += [testCase(ConvertToPerlTests.allTests)]
tests += [testCase(ObjectTests.allTests)]
tests += [testCase(BenchmarkTests.allTests)]
tests += [testCase(PerlCoroTests.allTests)]
XCTMain(tests)
