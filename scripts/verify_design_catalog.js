// Run with playwright-cli run-code --filename=scripts/verify_design_catalog.js.
// Verification output is returned as JSON; this file does not modify design sources.
async page=>{
 const base='http://127.0.0.1:4311/prototypes/picsee-browser/states/';
 const errors=[],failures=[],results=[];page.on('pageerror',e=>errors.push(e.message));page.on('response',r=>{if(r.status()>=400&&r.url().startsWith('http://127.0.0.1:'))failures.push({url:r.url(),status:r.status()})});
 await page.goto(base+'index.html');await page.getByRole('navigation',{name:'设计页面'}).waitFor();
 const catalog=await page.evaluate(async()=>{const r=await fetch('manifest.json');return r.json()});
 if(catalog.states.length!==20||await page.locator('nav button').count()!==20)throw Error('Expected 20 catalog states');
 for(const state of catalog.states){
  await page.setViewportSize(state.viewport);await page.goto(base+state.file);await page.evaluate(async()=>Promise.all([...document.images].map(i=>i.decode().catch(()=>{}))));
  const check=await page.evaluate(()=>({broken:[...document.images].some(i=>!i.complete||!i.naturalWidth),overflow:document.documentElement.scrollWidth>innerWidth,inlineImages:[...document.images].some(i=>i.src.startsWith('data:')),externalImages:[...document.images].some(i=>!i.src.startsWith(location.origin))}));
  if(Object.values(check).some(Boolean))throw Error(state.name+' invalid resource/layout '+JSON.stringify(check));
  if(state.name==='viewer-quiet'&&await page.locator('.zoom-pod').isVisible())throw Error('Quiet controls regression');
  if(state.name==='viewer-controls'&&!await page.locator('.zoom-pod').isVisible())throw Error('Visible controls regression');
  if(state.name==='grid-multiselect'&&await page.locator('.photo-cell[aria-selected="true"]').count()!==3)throw Error('Selection count regression');
  if(state.name==='viewer-filmstrip'&&(await page.locator('.c-filmstrip-images button').count()!==12||await page.locator('.navigation-pod').count()))throw Error('Filmstrip regression');
  results.push({name:state.name,passed:true});
 }
 // Each manifest sha256 pins the exact bytes of its page.
 for(const state of catalog.states){const actual=await page.evaluate(async f=>[...new Uint8Array(await crypto.subtle.digest('SHA-256',await(await fetch(f,{cache:'no-store'})).arrayBuffer()))].map(b=>b.toString(16).padStart(2,'0')).join(''),state.file);if(actual!==state.sha256)throw Error(state.file+' SHA256 mismatch: manifest '+state.sha256+', actual '+actual)}
 // Sub-cases of 22-BD and 26-BC (ADR-014) are reachable by query; the bare URL is the pinned main case.
 const subcases=[
  ['empty-folder.html',{tiles:3,recents:0,buttons:['包含子文件夹浏览','选择其他文件夹…'],drop:true}],
  ['empty-folder.html?case=no-subfolders',{tiles:0,minRecents:1,maxRecents:10,buttons:['选择其他文件夹…'],drop:true}],
  ['empty-folder.html?theme=dark',{dark:true,tiles:3}],
  ['empty-folder.html?drag=over',{tiles:3,dragOver:true}],
  ['permission-denied.html',{unavailable:true,buttons:['重新选择文件夹…','选择其他文件夹…']}],
  ['permission-denied.html?cause=volume',{unavailable:true,text:'等待磁盘连接',buttons:['选择其他文件夹…'],absent:['重新选择文件夹…']}],
  ['permission-denied.html?cause=missing',{unavailable:true,text:'找不到',buttons:['在新位置选择…','选择其他文件夹…']}],
  ['permission-denied.html?cause=unknown',{unavailable:true,text:'无法访问此文件夹',buttons:['重新选择文件夹…','选择其他文件夹…']}],
  ['permission-denied.html?case=moved',{unavailable:false,strip:'不是这个？选择其他文件夹…',cells:true}],
  ['permission-denied.html?theme=dark',{dark:true,unavailable:true}],
 ];
 const subcaseFailures=[];
 for(const [url,want] of subcases){
  await page.setViewportSize({width:1280,height:800});await page.goto(base+url);await page.evaluate(async()=>Promise.all([...document.images].map(i=>i.decode().catch(()=>{}))));
  const got=await page.evaluate(()=>{const visible=e=>!!e&&e.getClientRects().length>0&&getComputedStyle(e).visibility!=='hidden';const buttons=[...document.querySelectorAll('main button')].filter(visible).map(b=>b.textContent.trim());const strip=document.querySelector('.follow-strip');return{dark:document.documentElement.classList.contains('theme-dark'),tiles:document.querySelectorAll('main .subfolder-tile').length,recents:document.querySelectorAll('main .recent-folder').length,buttons,text:document.querySelector('main').innerText,drop:!!document.querySelector('main [data-drop-target]'),dragOver:!!document.querySelector('main [data-drop-target].is-drag-over'),unavailable:!!document.querySelector('.sidebar .ds-nav-row.is-unavailable .row-warning'),collapsed:!document.querySelector('.sidebar .is-unavailable + .folder-children'),strip:strip&&visible(strip)?strip.innerText:'',cells:document.querySelectorAll('main .photo-cell').length,shell:visible(document.querySelector('.sidebar'))&&visible(document.querySelector('.grid-bottom-bar')),broken:[...document.images].some(i=>!i.complete||!i.naturalWidth),overflow:document.documentElement.scrollWidth>innerWidth}});
  const bad=[];if(!got.shell)bad.push('sidebar/footer missing');if(got.broken||got.overflow)bad.push('resource/layout');
  if(want.dark&&!got.dark)bad.push('not dark');if('tiles' in want&&got.tiles!==want.tiles)bad.push('tiles '+got.tiles);if('recents' in want&&got.recents!==want.recents)bad.push('recents '+got.recents);
  if(want.minRecents&&(got.recents<want.minRecents||got.recents>want.maxRecents))bad.push('recents '+got.recents);if(want.drop&&!got.drop)bad.push('no drop target');if(want.dragOver&&!got.dragOver)bad.push('no drag-over affordance');
  for(const b of want.buttons||[])if(!got.buttons.includes(b))bad.push('missing button '+b);for(const b of want.absent||[])if(got.buttons.includes(b))bad.push('unexpected button '+b);
  if(want.text&&!got.text.includes(want.text))bad.push('missing text '+want.text);if('unavailable' in want&&got.unavailable!==want.unavailable)bad.push('sidebar unavailable='+got.unavailable);
  if(want.unavailable&&!got.collapsed)bad.push('subfolders not collapsed');if(want.strip&&!got.strip.includes(want.strip))bad.push('missing strip');if(want.cells&&!got.cells)bad.push('no grid');
  if(bad.length)subcaseFailures.push(url+': '+bad.join(', '));
 }
 if(subcaseFailures.length)throw Error('22/26 sub-cases: '+subcaseFailures.join(' | '));
 // journeys.html: linked from the index, success-path playback, branches return, no hand-typed status, no prototype files.
 await page.setViewportSize({width:1440,height:900});await page.goto(base+'index.html');await page.getByRole('navigation',{name:'设计页面'}).waitFor();
 if(!await page.locator('a[href="journeys.html"]').count())throw Error('index.html does not link journeys.html');
 const jr=await page.goto(base+'journeys.html');if(!jr||!jr.ok())throw Error('journeys.html missing');await page.locator('section.journey#J1').waitFor();
 const journeyIssues=await page.evaluate(()=>{const issues=[];const html=document.documentElement.outerHTML;
  if(/prototype-[\w-]*\.html/.test(html))issues.push('references a prototype file');if(document.querySelector('.st')||/部分真机|仅单元|未开始/.test(document.body.innerText))issues.push('hand-typed status badges');
  for(const id of ['ENTRY','J1','J2','J3','J4','REF'])if(!document.getElementById(id))issues.push('missing section '+id);
  if(document.querySelectorAll('#ENTRY tbody tr').length<6)issues.push('entry table has fewer than 6 entrances');
  const branches=[...document.querySelectorAll('[data-branch]')];if(!branches.length)issues.push('no branches');
  for(const b of branches){if(!b.dataset.to)issues.push('branch without to: '+b.dataset.branch);else if(!b.querySelector('.ret'))issues.push('branch without return edge: '+b.dataset.branch)}
  return issues});
 const journeyIds=await page.locator('section.journey[data-main]').evaluateAll(s=>s.map(e=>e.id));
 for(const id of journeyIds){
  const main=JSON.parse(await page.locator('#'+id).getAttribute('data-main'));const play=page.locator('#'+id+' button.play');await play.click();
  if(!await page.evaluate(()=>!!document.activeElement.closest('#player')))journeyIssues.push(id+': focus not in player');
  const played=[];for(let n=0;n<40;n++){played.push(await page.locator('#player').getAttribute('data-page'));const next=page.locator('#p-next');if(await next.isDisabled())break;await next.click()}
  if(JSON.stringify(played)!==JSON.stringify(main))journeyIssues.push(id+': played '+played.join(',')+' instead of main path '+main.join(','));
  for(let n=0;n<12;n++)await page.keyboard.press('Tab');if(!await page.evaluate(()=>!!document.activeElement.closest('#player')))journeyIssues.push(id+': Tab left the player');
  await page.keyboard.press('Escape');if(await page.locator('#player').isVisible())journeyIssues.push(id+': Esc did not close');
  if(!await page.evaluate(i=>document.activeElement===document.querySelector('#'+i+' button.play'),id))journeyIssues.push(id+': focus did not return');
 }
 if(journeyIds.length<4)journeyIssues.push('expected J1–J4 with data-main, got '+journeyIds.join(','));
 if(journeyIssues.length)throw Error('journeys.html: '+journeyIssues.join(' | '));
 await page.setViewportSize({width:1280,height:800});await page.goto('http://127.0.0.1:4313/index.html');await page.getByRole('navigation',{name:'设计页面'}).waitFor();
 await page.getByRole('button',{name:'33 胶片条展开 · C',exact:true}).click();await page.frameLocator('iframe').locator('.c-filmstrip').waitFor();
 await page.screenshot({path:'evidence/design-material-preview.png'});
 await page.goto('http://127.0.0.1:4311/prototypes/picsee-browser/viewer-v2.html');await page.getByTestId('large-viewer').waitFor();await page.keyboard.press('Escape');if(await page.locator('.photo-cell').count()!==12)throw Error('Interactive prototype regression');
 if(errors.length||failures.length)throw Error(JSON.stringify({errors,failures}));return{passed:true,stateCount:results.length,hashesPinned:catalog.states.length,subcases:subcases.length,journeys:journeyIds,canonicalPreview:true,legacy4313Preview:true,interactivePrototype:true,results,errors,failures};
}
