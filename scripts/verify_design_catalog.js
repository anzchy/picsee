// Run with `npm run design:check` (scripts/design-check.mjs serves design/ and states/ and passes their origins).
// Verification output is returned as JSON; this file does not modify design sources.
// Each branch's played destinations, written from plan §1.6, ADR-0010 and ADR-014 rather than read from journeys.html.
// A page with a query is written page?query. Branches without a state page (placeholders, menu actions) have no player.
const BRANCH_PLAYS={
 'J1-cancel':[['first-launch','folder-loading','first-launch'],['grid-light','folder-loading','grid-light']],
 'J1-empty':[['folder-loading','empty-folder','folder-loading']],
 'J1-access':[['grid-light','permission-denied','grid-light'],['grid-light','permission-denied','permission-denied'],['grid-light','permission-denied','folder-loading'],['grid-light','permission-denied?cause=volume','grid-light']],
 'J1-moved':[['grid-light','permission-denied?case=moved','grid-light'],['grid-light','permission-denied?case=moved','folder-loading']],
 'J2-error':[['viewer-quiet','image-error','viewer-quiet'],['viewer-quiet','image-error','grid-light']],
 'J2-tools':[['viewer-quiet','viewer-controls','viewer-quiet']],
 'J2-actual':[['viewer-quiet','original-size','viewer-quiet']],
 'J2-film':[['viewer-quiet','viewer-filmstrip','viewer-quiet']],
 'J3-search':[['grid-light','search-empty','grid-light']],
 'J4-light':[['viewer-inspector','viewer-inspector-light','viewer-inspector']],
};
module.exports=async(page,{design,states,screenshot})=>{
 const base=design+'/prototypes/picsee-browser/states/';
 const errors=[],failures=[],results=[];page.on('pageerror',e=>errors.push(e.message));page.on('response',r=>{if(r.status()>=400&&r.url().startsWith('http://127.0.0.1:'))failures.push({url:r.url(),status:r.status()})});
 await page.goto(base+'index.html');await page.getByRole('navigation',{name:'设计页面'}).waitFor();
 const catalog=await page.evaluate(async()=>{const r=await fetch('manifest.json');return r.json()});
 if(catalog.states.length!==20||await page.locator('nav button').count()!==20)throw Error('Expected 20 catalog states');

 // 22 and 26 are local replacements of the accepted Stitch pages (ADR-014), like 31–34.
 for(const name of ['empty-folder','permission-denied'])if(catalog.states.find(s=>s.name===name).origin!=='local-C-adaptation')throw Error(name+' origin is not local-C-adaptation');
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
  ['permission-denied.html?cause=volume',{unavailable:true,text:'等待磁盘连接',texts:['重新确认访问权限'],notText:['不需要再选择'],buttons:['选择其他文件夹…'],absent:['重新选择文件夹…']}],
  ['permission-denied.html?cause=missing',{unavailable:true,text:'找不到',buttons:['在新位置选择…','选择其他文件夹…']}],
  ['permission-denied.html?cause=unknown',{unavailable:true,text:'无法访问此文件夹',buttons:['重新选择文件夹…','选择其他文件夹…']}],
  ['permission-denied.html?case=moved',{unavailable:false,strip:'不是这个？选择其他文件夹…',cells:true}],
  ['permission-denied.html?theme=dark',{dark:true,unavailable:true}],
 ];
 const subcaseFailures=[];
 for(const [url,want] of subcases){
  await page.setViewportSize({width:1280,height:800});await page.goto(base+url);await page.evaluate(async()=>Promise.all([...document.images].map(i=>i.decode().catch(()=>{}))));
  // orphanLine: no line of #state-text may hold only one or two characters (the 「次。」 wrap). Line breaks depend on the
  // fonts headless Chromium resolves, so the copy is measured at letter-spacing −1…+1 px to stand in for wider and narrower glyphs.
  const got=await page.evaluate(()=>{const visible=e=>!!e&&e.getClientRects().length>0&&getComputedStyle(e).visibility!=='hidden';const buttons=[...document.querySelectorAll('main button')].filter(visible).map(b=>b.textContent.trim());const strip=document.querySelector('.follow-strip');return{dark:document.documentElement.classList.contains('theme-dark'),tiles:document.querySelectorAll('main .subfolder-tile').length,recents:document.querySelectorAll('main .recent-folder').length,buttons,text:document.querySelector('main').innerText,drop:!!document.querySelector('main [data-drop-target]'),dragOver:!!document.querySelector('main [data-drop-target].is-drag-over'),unavailable:!!document.querySelector('.sidebar .ds-nav-row.is-unavailable .row-warning'),collapsed:(r=>!!r&&r.getAttribute('aria-expanded')==='false'&&visible(r.querySelector('.row-disclosure'))&&!document.querySelector('.sidebar .folder-children'))(document.querySelector('.sidebar .ds-nav-row.is-unavailable')),pendingRows:[...document.querySelectorAll('.sidebar .ds-nav-row')].filter(r=>/个人收藏|最近查看/.test(r.innerText)).map(r=>r.dataset.pending==='P3-14'),pendingHeading:(m=>!!m&&visible(m)&&m.innerText.includes('PENDING(P3-14)'))(document.querySelector('.sidebar .library-toggle [data-pending="P3-14"]')),pendingSentence:(e=>!e||(!!e.closest('[data-pending="P3-14"]')&&e.closest('[data-pending="P3-14"]').innerText.includes('PENDING(P3-14)')))([...document.querySelectorAll('#state-text *, #state-text')].find(e=>[...e.childNodes].some(n=>n.nodeType===3&&n.textContent.includes('收藏和最近查看')))),sentence:document.querySelector('main').innerText.includes('收藏和最近查看'),tileLabels:[...document.querySelectorAll('main .subfolder-tile')].map(t=>t.getAttribute('aria-label')||''),tileGroup:(g=>!g||g.getAttribute('role')==='group')(document.querySelector('main .subfolder-tiles')),orphanLine:(p=>{if(!p)return '';for(let t=-10;t<=10;t++){p.style.letterSpacing=t/10+'px';const lines=new Map();const walk=document.createTreeWalker(p,NodeFilter.SHOW_TEXT);for(let n;(n=walk.nextNode());)for(let i=0;i<n.length;i++){if(!n.textContent[i].trim())continue;const r=document.createRange();r.setStart(n,i);r.setEnd(n,i+1);const b=r.getClientRects()[0];if(!b)continue;const k=Math.round(b.top);lines.set(k,(lines.get(k)||'')+n.textContent[i])}const o=[...lines.values()].find(l=>l.length<=2);if(o){p.style.letterSpacing='';return o+' at letter-spacing '+t/10+'px'}}p.style.letterSpacing='';return ''})(document.querySelector('#state-text')),strip:strip&&visible(strip)?strip.innerText:'',cells:document.querySelectorAll('main .photo-cell').length,shell:visible(document.querySelector('.sidebar'))&&visible(document.querySelector('.grid-bottom-bar')),broken:[...document.images].some(i=>!i.complete||!i.naturalWidth),overflow:document.documentElement.scrollWidth>innerWidth}});
  const bad=[];if(!got.shell)bad.push('sidebar/footer missing');if(got.broken||got.overflow)bad.push('resource/layout');
  if(want.dark&&!got.dark)bad.push('not dark');if('tiles' in want&&got.tiles!==want.tiles)bad.push('tiles '+got.tiles);if('recents' in want&&got.recents!==want.recents)bad.push('recents '+got.recents);
  if(want.minRecents&&(got.recents<want.minRecents||got.recents>want.maxRecents))bad.push('recents '+got.recents);if(want.drop&&!got.drop)bad.push('no drop target');if(want.dragOver&&!got.dragOver)bad.push('no drag-over affordance');
  for(const b of want.buttons||[])if(!got.buttons.includes(b))bad.push('missing button '+b);for(const b of want.absent||[])if(got.buttons.includes(b))bad.push('unexpected button '+b);
  if(want.text&&!got.text.includes(want.text))bad.push('missing text '+want.text);if('unavailable' in want&&got.unavailable!==want.unavailable)bad.push('sidebar unavailable='+got.unavailable);
  if(want.unavailable&&!got.collapsed)bad.push('subfolders not drawn collapsed (aria-expanded=false + disclosure)');if(url.startsWith('permission-denied')){if(got.pendingRows.length!==2||!got.pendingRows.every(Boolean)||!got.pendingHeading)bad.push('个人收藏/最近查看 rows not marked PENDING(P3-14)');if(want.unavailable&&!got.sentence)bad.push('missing 收藏和最近查看 sentence');if(!got.pendingSentence)bad.push('收藏和最近查看 sentence not marked PENDING(P3-14)')}if(!got.tileGroup)bad.push('subfolder tiles not a group');for(const l of got.tileLabels)if(!/^\S.*，子文件夹$/.test(l))bad.push('tile label '+JSON.stringify(l));if(got.orphanLine)bad.push('orphan line '+JSON.stringify(got.orphanLine));for(const s of want.texts||[])if(!got.text.includes(s))bad.push('missing text '+s);for(const s of want.notText||[])if(got.text.includes(s))bad.push('unexpected text '+s);if(want.strip&&!got.strip.includes(want.strip))bad.push('missing strip');if(want.cells&&!got.cells)bad.push('no grid');
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
  const rows=[...document.querySelectorAll('#ENTRY tbody tr')].map(r=>r.innerText.replace(/\s+/g,' '));if(rows.length<8)issues.push('entry table has fewer than 8 entrances');
  // ADR-0010, OPEN-03/04, ACCESS-01: a single image inside an access root scans without a prompt and Esc goes 24 → 11;
  // outside every root → asks for access and stays in the viewer, and Esc does nothing.
  for(const [what,re] of [['Finder',/访达/],['image drop',/图片拖进窗口/]]){const pair=rows.filter(r=>re.test(r));
   if(pair.length!==2)issues.push(what+' entrance is not split into in-root / not-in-root rows');
   else{if(!pair.some(r=>/(?<!不在)授权范围内/.test(r)&&/不弹授权/.test(r)&&/Esc\s*→\s*24[^]*→\s*11/.test(r)&&/当前项/.test(r)))issues.push(what+': in-root row lacks Esc → 24 → 11 with this image current, no prompt');
    if(!pair.some(r=>/不在授权范围/.test(r)&&/ACCESS-01/.test(r)&&/留在大图/.test(r)&&/Esc\s*无变化/.test(r)))issues.push(what+': not-in-root row lacks → asks for access, stays in viewer, Esc does nothing')}}
  const moved=document.querySelector('[data-branch="J1-moved"] .card');if(!moved||!/26M-C 已跟随到新位置/.test(moved.innerText)||/权限失效/.test(moved.innerText))issues.push('J1-moved card is not titled 26M-C 已跟随到新位置');
  const j4=[...document.querySelectorAll('#J4 .arrow .lab')].map(l=>l.innerHTML);if(!j4.some(l=>(l.match(/<kbd>Esc<\/kbd>/g)||[]).length>=2&&/Inspector/.test(l)))issues.push('J4: Esc order is not two steps');
  const access=document.querySelector('[data-branch="J1-access"]');if(!access||!/选择其他文件夹/.test(access.innerText)||!/自动恢复/.test(access.innerText))issues.push('J1-access lacks 选择其他文件夹… and auto-recovery after mount');
  const branches=[...document.querySelectorAll('[data-branch]')];if(!branches.length)issues.push('no branches');
  for(const b of branches){if(!b.dataset.to)issues.push('branch without to: '+b.dataset.branch);else if(!b.querySelector('.ret'))issues.push('branch without return edge: '+b.dataset.branch)}
  return issues});
 const journeyIds=await page.locator('section.journey[data-main]').evaluateAll(s=>s.map(e=>e.id));
 for(const id of journeyIds){
  const main=JSON.parse(await page.locator('#'+id).getAttribute('data-main'));const play=page.locator('#'+id+' button.play');await play.click();
  if(!await page.evaluate(()=>!!document.activeElement.closest('#player')))journeyIssues.push(id+': focus not in player');
  const played=[];for(let n=0;n<40;n++){played.push(await page.locator('#player').getAttribute('data-page'));const next=page.locator('#p-next');if(await next.isDisabled())break;await next.click()}
  if(JSON.stringify(played)!==JSON.stringify(main))journeyIssues.push(id+': played '+played.join(',')+' instead of main path '+main.join(','));
  // A click inside the preview must not take the player's keys: Esc still closes and Tab stays in the dialog.
  const box=await page.locator('#p-frame').boundingBox();await page.mouse.click(box.x+box.width/2,box.y+box.height/2);
  await page.keyboard.press('Tab');if(!await page.evaluate(()=>!!document.activeElement.closest('#player')&&document.activeElement.tagName!=='IFRAME'))journeyIssues.push(id+': Tab after a click in the preview left the player controls');
  await page.mouse.click(box.x+box.width/2,box.y+box.height/2);await page.keyboard.press('Escape');if(await page.locator('#player').isVisible()){journeyIssues.push(id+': Esc after a click in the preview did not close');await page.locator('#p-close').click()}
  await play.click();
  for(let n=0;n<12;n++)await page.keyboard.press('Tab');if(!await page.evaluate(()=>!!document.activeElement.closest('#player')))journeyIssues.push(id+': Tab left the player');
  await page.keyboard.press('Escape');if(await page.locator('#player').isVisible())journeyIssues.push(id+': Esc did not close');
  if(!await page.evaluate(i=>document.activeElement===document.querySelector('#'+i+' button.play'),id))journeyIssues.push(id+': focus did not return');
 }
 if(journeyIds.length<4)journeyIssues.push('expected J1–J4 with data-main, got '+journeyIds.join(','));
 // Every branch outcome plays from its start through the branch page to its real destination.
 const branchPlayed={};let branchPlays=0;
 for(const button of await page.locator('[data-play-branch]').all()){
  const id=await button.getAttribute('data-play-branch');await button.click();const played=[];
  for(let n=0;n<10;n++){played.push(await page.locator('#player').evaluate(p=>p.dataset.page+(p.dataset.query?'?'+p.dataset.query:'')));const next=page.locator('#p-next');if(await next.isDisabled())break;await next.click()}
  (branchPlayed[id]=branchPlayed[id]||[]).push(played);branchPlays++;await page.keyboard.press('Escape');
 }
 const sortedJSON=o=>JSON.stringify(Object.keys(o).sort().map(k=>[k,o[k].map(s=>s.join('>')).sort()]));
 if(sortedJSON(branchPlayed)!==sortedJSON(BRANCH_PLAYS))for(const id of new Set([...Object.keys(BRANCH_PLAYS),...Object.keys(branchPlayed)])){const want=(BRANCH_PLAYS[id]||[]).map(s=>s.join('>')).sort(),got=(branchPlayed[id]||[]).map(s=>s.join('>')).sort();if(JSON.stringify(want)!==JSON.stringify(got))journeyIssues.push(id+': branch plays '+(got.join(' ; ')||'none')+' instead of '+(want.join(' ; ')||'none'))}
 if(journeyIssues.length)throw Error('journeys.html: '+journeyIssues.join(' | '));
 await page.setViewportSize({width:1280,height:800});await page.goto(states+'/index.html');await page.getByRole('navigation',{name:'设计页面'}).waitFor();
 await page.getByRole('button',{name:'33 胶片条展开 · C',exact:true}).click();await page.frameLocator('iframe').locator('.c-filmstrip').waitFor();
 if(screenshot)await page.screenshot({path:screenshot});
 await page.goto(design+'/prototypes/picsee-browser/viewer-v2.html');await page.getByTestId('large-viewer').waitFor();await page.keyboard.press('Escape');if(await page.locator('.photo-cell').count()!==12)throw Error('Interactive prototype regression');
 if(errors.length||failures.length)throw Error(JSON.stringify({errors,failures}));return{passed:true,stateCount:results.length,hashesPinned:catalog.states.length,subcases:subcases.length,journeys:journeyIds,branchPlays,canonicalPreview:true,legacy4313Preview:true,interactivePrototype:true,results,errors,failures};
};
