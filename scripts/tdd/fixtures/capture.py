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
with (h/'fixture-capture.txt').open('w') as log:
 for name,source in [('swift-pass',swift.replace('VALUE','1').replace('#expect(2 == 1)','#expect(2 == 2)')),('swift-fail',swift.replace('VALUE','0')),('compile-fail',swift.replace('VALUE','missingFixtureSymbol')),('xctest-fail',xct.replace('VALUE','0')),('xctest-pass',xct.replace('VALUE','1'))]:
  t.write_text(source)
  (h/(name+'.swift')).write_text(source)
  cmd=['swift','test','--package-path',str(s)]
  r=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
  (f/(name+'.txt')).write_bytes(r.stdout)
  log.write('$ '+' '.join(cmd)+'\nsource='+name+'.swift\nexit='+str(r.returncode)+'\n'+r.stdout.decode()+'\n')
  print(name, r.returncode, r.stdout.decode()[-1800:])
