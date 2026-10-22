from pathlib import Path
import subprocess
import sys
s=Path(sys.argv[1]).resolve()  # existing scratch Swift package; see README.md
h=s.parent
f=Path(__file__).resolve().parent
t=s/'Tests/LaneTests/FixtureTests.swift'
swift="""import Testing
@Test func passing() { #expect(1 == 1) }
@Test func failing() { #expect(1 == VALUE); #expect(2 == VALUE) }
@Test(.disabled("fixture skip")) func skipped() { }
"""
xct='import XCTest\nfinal class FixtureTests: XCTestCase {\n'+''.join('func test%02d() throws %s\n'%(i, '{ throw XCTSkip("fixture skip") }' if i==11 else '{ XCTAssertEqual(1, VALUE) }' if i==0 else '{ XCTAssertEqual(1, 1) }') for i in range(12))+'}\n'
duplicate = """import Testing
@Test("same") func first() { #expect(1 == 0) }
@Test("same") func second() { #expect(2 == 0) }
@Test("same", .disabled("fixture skip one")) func skippedFirst() { }
@Test("same", .disabled("fixture skip two")) func skippedSecond() { }
"""
crash = """import XCTest
final class AAssertionTests: XCTestCase {
    func testFirst() { XCTAssertEqual(1, 0) }
}
final class BCrashTests: XCTestCase {
    func testSecond() { fatalError("intentional fixture trap") }
}
"""
with (h/'fixture-capture.txt').open('w') as log:
 for name,source in [('swift-pass',swift.replace('VALUE','1').replace('#expect(2 == 1)','#expect(2 == 2)')),('swift-fail',swift.replace('VALUE','0')),('compile-fail',swift.replace('VALUE','missingFixtureSymbol')),('xctest-fail',xct.replace('VALUE','0')),('xctest-pass',xct.replace('VALUE','1')),('swift-duplicate',duplicate),('xctest-partial-crash',crash)]:
  t.write_text(source)
  (h/(name+'.swift')).write_text(source)
  cmd=['swift','test','--package-path',str(s)]
  r=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
  # Normalize only filesystem prefixes; retain all result and diagnostic lines.
  neutral=r.stdout.decode().replace(str(s), '/SCRATCH/LaneFixtures').replace(str(Path.home()), '/HOME')
  (f/(name+'.txt')).write_text(neutral)
  log.write('$ '+' '.join(cmd)+'\nsource='+name+'.swift\nexit='+str(r.returncode)+'\n'+r.stdout.decode()+'\n')
  print(name, r.returncode, r.stdout.decode()[-1800:])
