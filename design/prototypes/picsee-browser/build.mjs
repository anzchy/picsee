import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
const require=createRequire(import.meta.url);
const base=path.dirname(fileURLToPath(import.meta.url));
const skill=process.env.BAOYU_DESIGN_HOME||path.join(os.homedir(),'.codex/skills/baoyu-design');
const Babel=require(path.join(skill,'agents/vendor/babel.min.js'));
for(const name of ['ui','app']){
 const result=Babel.transform(fs.readFileSync(path.join(base,name+'.jsx'),'utf8'),{presets:[['react',{runtime:'classic'}]],filename:name+'.jsx'});
 fs.writeFileSync(path.join(base,name+'.js'),result.code);
}
console.log('Compiled ui.jsx and app.jsx. No browser-side compilation or network dependency.');
