async page=>{
 const out='design/prototypes/picsee-browser/qa';
 const checks=[],errors=[];page.on('pageerror',e=>errors.push(e.message));
 const check=(value,label)=>{if(!value)throw Error(label);checks.push(label)};
 await page.setViewportSize({width:1019,height:853});await page.goto('http://127.0.0.1:4311/prototypes/picsee-browser/viewer-v2.html');
 await page.evaluate(()=>Object.keys(localStorage).filter(k=>k.startsWith('picsee-v2-')).forEach(k=>localStorage.removeItem(k)));await page.reload();
 await page.getByTestId('large-viewer').waitFor();await page.keyboard.press('Escape');
 check(await page.locator('.photo-caption,.selected-check,.sidebar-bottom,.titlebar-actions,.app-brand').count()===0,'Removed captions, selection badges, demo copy and titlebar tools');
 check(await page.locator('.photo-cell').count()===12,'12 photos remain');
 check(await page.getByRole('slider',{name:'缩略图大小'}).count()===0,'Density slider is not persistent');
 await page.getByRole('button',{name:'显示侧栏',exact:true}).click();
 const separator=page.getByRole('separator',{name:'调整侧栏宽度'});await separator.focus();await page.keyboard.press('ArrowRight');check(await separator.getAttribute('aria-valuenow')==='206','Sidebar resizes by keyboard');
 await page.getByRole('button',{name:'图库',exact:true}).click();check(await page.getByRole('button',{name:'所有照片 12',exact:true}).count()===0,'Library section collapses');await page.getByRole('button',{name:'图库',exact:true}).click();
 await page.getByRole('button',{name:'显示与外观',exact:true}).click();check(await page.getByRole('combobox',{name:'外观',exact:true}).inputValue()==='system','Appearance defaults to system');
 await page.getByRole('combobox',{name:'外观',exact:true}).selectOption('light');
 await page.getByRole('checkbox',{name:'显示文件名',exact:true}).uncheck();check(await page.locator('.photo-name').count()===0,'Photo-only grid works');await page.getByRole('checkbox',{name:'显示文件名',exact:true}).check();
 await page.getByRole('combobox',{name:'缩略图显示方式'}).selectOption('contain');check(await page.locator('.thumb-contain').count()===12,'Full-thumbnail display works');await page.getByRole('combobox',{name:'缩略图显示方式'}).selectOption('cover');
 await page.getByRole('slider',{name:'缩略图大小'}).fill('220');await page.getByRole('button',{name:'关闭显示面板'}).click();
 await page.evaluate(async()=>Promise.all([...document.images].map(i=>i.decode().catch(()=>{}))));await page.screenshot({path:out+'/draft2-grid-light.png'});
 await page.keyboard.press('Meta+f');await page.getByRole('searchbox',{name:'搜索当前文件夹'}).fill('0343');await page.keyboard.press('Escape');check(await page.locator('.active-search').isVisible(),'Active filter remains visible after popover closes');await page.locator('.active-search').click();check(await page.locator('.photo-cell').count()===12,'Visible filter chip restores all photos');
 await page.getByRole('button',{name:'图片排序',exact:true}).click();await page.getByRole('combobox',{name:'排序方式'}).selectOption('date');check(await page.locator('.photo-name').first().textContent()==='DSC_0351.jpg','Sorting works');await page.getByRole('combobox',{name:'排序方式'}).selectOption('name');await page.keyboard.press('Escape');
 await page.getByRole('button',{name:'显示与外观',exact:true}).click();await page.getByRole('combobox',{name:'外观',exact:true}).selectOption('dark');await page.getByRole('button',{name:'关闭显示面板'}).click();check(await page.locator('html').getAttribute('class')==='theme-dark','Dark theme works');await page.screenshot({path:out+'/draft2-grid-dark.png'});
 await page.getByRole('button',{name:'隐藏侧栏',exact:true}).click();await page.locator('[data-photo-id="lakeside"]').click();await page.keyboard.press('Space');await page.getByTestId('large-viewer').waitFor();check(await page.locator('.picture-stage').evaluate(e=>e.clientHeight)===853,'Viewer uses full height');
 await page.keyboard.press('ArrowRight');check((await page.locator('.large-image').getAttribute('src')).includes('temple'),'Right arrow browses');await page.keyboard.press('ArrowLeft');
 await page.keyboard.press('1');check(await page.locator('.large-image').evaluate(e=>Math.abs(e.getBoundingClientRect().width-e.naturalWidth/devicePixelRatio)<1),'1:1 is based on source pixels');
 await page.keyboard.press('0');check(await page.getByRole('combobox',{name:'缩放模式'}).inputValue()==='fit','0 returns to fit');
 await page.locator('.picture-stage').click({position:{x:450,y:250}});await page.waitForFunction(()=>document.querySelector('.picture-viewer').classList.contains('chrome-asleep'));check(!await page.locator('.zoom-pod').isVisible(),'Controls hide after inactivity');await page.screenshot({path:out+'/draft2-viewer-quiet.png'});
 await page.keyboard.press('Tab');await page.waitForFunction(()=>document.activeElement?.getAttribute('aria-label')==='显示侧栏');check(await page.locator('.zoom-pod').isVisible(),'Tab restores controls and focus');
 await page.getByRole('button',{name:'更多浏览操作'}).click();await page.getByRole('checkbox',{name:'始终显示工具',exact:true}).check();await page.keyboard.press('Escape');await page.locator('.picture-stage').click({position:{x:450,y:250}});await page.waitForTimeout(2900);check(await page.locator('.zoom-pod').isVisible(),'Always-visible preference prevents hiding');await page.screenshot({path:out+'/draft2-viewer-controls.png'});
 await page.keyboard.press('Escape');check(await page.locator('[data-photo-id="lakeside"]').getAttribute('aria-selected')==='true','Esc preserves selection');check(await page.locator('.keyboard-hint').count()===0,'Learned Space hint is removed');
 await page.getByRole('button',{name:'显示与外观'}).click();await page.getByRole('combobox',{name:'外观',exact:true}).selectOption('system');await page.getByRole('button',{name:'关闭显示面板'}).click();await page.emulateMedia({colorScheme:'light'});await page.waitForFunction(()=>document.documentElement.className==='theme-light');await page.emulateMedia({colorScheme:'dark'});await page.waitForFunction(()=>document.documentElement.className==='theme-dark');check(true,'System appearance changes live');
 await page.reload();await page.getByTestId('large-viewer').waitFor();check(await page.locator('.zoom-pod').isVisible(),'Viewer preference survives reload');await page.keyboard.press('Escape');
 for(const width of [800,480,390]){await page.setViewportSize({width,height:680});check(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'No page overflow at '+width+'px')}
 await page.setViewportSize({width:1019,height:853});await page.getByRole('button',{name:'显示与外观'}).click();await page.getByRole('combobox',{name:'外观',exact:true}).selectOption('light');await page.getByRole('checkbox',{name:'始终显示大图工具'}).uncheck();await page.getByRole('button',{name:'关闭显示面板'}).click();
 check(!errors.length,'No runtime errors');return{passed:true,checks:checks.length,results:checks,errors};
}
