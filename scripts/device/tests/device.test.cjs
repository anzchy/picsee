const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {spawn,spawnSync}=require('node:child_process');
const base=path.resolve(__dirname,'..');
const scratch=path.join(os.homedir(),'.picsee/device-runs/tests-'+Date.now());
fs.mkdirSync(scratch,{recursive:true});
function call(name,args){return spawnSync(path.join(base,name+'.sh'),args,{encoding:'utf8'});}
function dummy(dir){fs.mkdirSync(dir,{recursive:true});const exe=path.join(dir,'sleep');fs.copyFileSync('/bin/sleep',exe);fs.chmodSync(exe,0o755);return spawn(exe,['120'],{stdio:'ignore'});}
function record(dir,pid,bundle){fs.mkdirSync(dir,{recursive:true});fs.writeFileSync(path.join(dir,'picsee.pid'),String(pid));fs.writeFileSync(path.join(dir,'bundle.path'),bundle);}
test('cleanup kills only recorded PID, spares same-name process',async()=>{
 const bundle=path.join(scratch,'Good.app'),one=dummy(path.join(bundle,'Contents/MacOS')),two=dummy(path.join(scratch,'other'));
 try {await new Promise(r=>setTimeout(r,100));const run=path.join(scratch,'cleanup-good');record(run,one.pid,bundle);const r=call('cleanup',[run]);assert.equal(r.status,0,r.stderr||r.error?.message);await new Promise(r=>setTimeout(r,100));assert.throws(()=>process.kill(one.pid,0));assert.doesNotThrow(()=>process.kill(two.pid,0));}
 finally{one.kill();two.kill();}
});
test('cleanup refuses executable outside recorded bundle',async()=>{
 const child=dummy(path.join(scratch,'outside'));
 try{await new Promise(r=>setTimeout(r,100));const run=path.join(scratch,'cleanup-wrong');record(run,child.pid,path.join(scratch,'Wrong.app'));const r=call('cleanup',[run]);assert.equal(r.status,1,r.error?.message);assert.match(r.stdout,/FAIL cleanup.*outside recorded bundle/);assert.doesNotThrow(()=>process.kill(child.pid,0));}finally{child.kill();}
});
const checks=['build-sha','bundle-id','signature-team','signature-valid','sandbox','process-bundle','fresh-sources','single-instance','window','launch-log','machine','fixtures'];
function fixture(){return {expectedSHA:'abc1234',sha:'abc1234',bundleID:'io.github.anzchy.picsee',team:'GRT84NAK4T',signatureValid:true,sandbox:true,processMatches:true,fresh:true,alone:true,windows:[{title:'Picsee'}],log:'Picsee launch git=abc1234',machineMatches:true,fixturesIntact:true};}
function doctor(input,name){const file=path.join(scratch,name+'.json');fs.writeFileSync(file,JSON.stringify(input));return call('doctor',['--fixture',file]);}
test('doctor emits exactly one PASS line per check',()=>{const r=doctor(fixture(),'pass');assert.equal(r.status,0,r.error?.message);assert.deepEqual(r.stdout.trim().split('\n'),checks.map(c=>'PASS '+c));});
test('doctor emits one result per check and fails on each individual defect',()=>{
 for(const [key,value] of Object.entries({sha:'old',bundleID:'wrong',team:'wrong',signatureValid:false,sandbox:false,processMatches:false,fresh:false,alone:false,windows:[],log:'<private>',machineMatches:false,fixturesIntact:false})){
 const f=fixture();f[key]=value;const r=doctor(f,'fail-'+key);assert.equal(r.status,1,key+': '+r.error?.message);const lines=r.stdout.trim().split('\n');assert.equal(lines.length,checks.length);for(let i=0;i<checks.length;i++)assert.match(lines[i],new RegExp('^(PASS '+checks[i]+'$|FAIL '+checks[i]+' — .+)'));assert.equal(lines.filter(l=>l.startsWith('FAIL')).length,1,key);
 }
});
test('window lookup uses PID even with identical or misleading owner names',()=>{
 const helper=require('../winid.js');const windows=[{kCGWindowOwnerPID:11,kCGWindowOwnerName:'Picsee',kCGWindowLayer:0,kCGWindowNumber:1},{kCGWindowOwnerPID:22,kCGWindowOwnerName:'Other',kCGWindowLayer:0,kCGWindowNumber:2},{kCGWindowOwnerPID:22,kCGWindowOwnerName:'Picsee',kCGWindowLayer:3,kCGWindowNumber:3}];
 assert.deepEqual(helper.selectWindows(windows,22).map(w=>w.kCGWindowNumber),[2]);
 assert.deepEqual(helper.selectWindows(windows,33),[]);
});
test('sandbox parser reads the current codesign text dump and XML without false positives',()=>{
 const script=`import sys
sys.path.insert(0, sys.argv[1])
from device import sandbox_enabled
assert sandbox_enabled('[Dict]\\n\\t[Key] com.apple.security.app-sandbox\\n\\t[Value]\\n\\t\\t[Bool] true\\n')
assert not sandbox_enabled('[Dict]\\n\\t[Key] com.apple.security.app-sandbox\\n\\t[Value]\\n\\t\\t[Bool] false\\n\\t[Key] other\\n\\t[Value]\\n\\t\\t[Bool] true\\n')
assert sandbox_enabled(b'<?xml version="1.0"?><plist version="1.0"><dict><key>com.apple.security.app-sandbox</key><true/></dict></plist>')
assert not sandbox_enabled('nonsense')`;
 const r=spawnSync('python3',['-c',script,base],{encoding:'utf8'});assert.equal(r.status,0,r.stderr);
});
