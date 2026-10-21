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
 await page.setViewportSize({width:1280,height:800});await page.goto('http://127.0.0.1:4313/index.html');await page.getByRole('navigation',{name:'设计页面'}).waitFor();
 await page.getByRole('button',{name:'33 胶片条展开 · C',exact:true}).click();await page.frameLocator('iframe').locator('.c-filmstrip').waitFor();
 await page.screenshot({path:'evidence/design-material-preview.png'});
 await page.goto('http://127.0.0.1:4311/prototypes/picsee-browser/viewer-v2.html');await page.getByTestId('large-viewer').waitFor();await page.keyboard.press('Escape');if(await page.locator('.photo-cell').count()!==12)throw Error('Interactive prototype regression');
 if(errors.length||failures.length)throw Error(JSON.stringify({errors,failures}));return{passed:true,stateCount:results.length,canonicalPreview:true,legacy4313Preview:true,interactivePrototype:true,results,errors,failures};
}
