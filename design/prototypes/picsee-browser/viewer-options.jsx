(function(){
const {useState,useEffect,useMemo,useRef,useLayoutEffect}=React;
const {IconButton,Keycap,NavRow}=window.PicseeUiSystem_bb8eab;
const Icon=window.PicseeIcon,Photo=window.PicseePhoto;
const {PictureViewer}=window.PicseeViewerLayouts;
function saved(key,fallback){try{return JSON.parse(localStorage.getItem(key))??fallback}catch{return fallback}}
function App(){
 const [appearance,setAppearance]=useState(()=>saved('picsee-v2-appearance','system'));
 const [systemDark,setSystemDark]=useState(()=>matchMedia('(prefers-color-scheme: dark)').matches);
 const theme=appearance==='system'?(systemDark?'dark':'light'):appearance;
 const [showNames,setShowNames]=useState(()=>saved('picsee-v2-names',true)),[thumbFit,setThumbFit]=useState(()=>saved('picsee-v2-thumb-fit','cover'));
 const [alwaysControls,setAlwaysControls]=useState(()=>saved('picsee-v2-controls',false)),[libraryOpen,setLibraryOpen]=useState(true);
 const [learned,setLearned]=useState(()=>saved('picsee-v2-learned',false));
 const [sidebarWidth,setSidebarWidth]=useState(()=>saved('picsee-v2-sidebar-width',196));
 const [photos,setPhotos]=useState(window.PICSEE_PHOTOS);
 const [folder,setFolder]=useState('japan');
 const [customFolders,setCustomFolders]=useState({});
 const [selected,setSelected]=useState('lakeside');
 const [viewer,setViewer]=useState(true);
 const variant='immersive';
 const [filmstrip,setFilmstrip]=useState(()=>saved('picsee-v2-filmstrip',false));
 const [gridTools,setGridTools]=useState(null);
 const [sidebar,setSidebar]=useState(()=>saved('picsee-v2-sidebar',false)),[inspector,setInspector]=useState(false);
 const [favorites,setFavorites]=useState(()=>saved('picsee-prototype-favorites',['alley','temple','shore']));
 const [recent,setRecent]=useState([]),[query,setQuery]=useState(''),[sortBy,setSortBy]=useState('name');
 const [cellSize,setCellSize]=useState(()=>saved('picsee-v2-cell-size',220)),[zoom,setZoom]=useState(null),[canvasSize,setCanvasSize]=useState({width:0,height:0,pixelRatio:1}),[pan,setPan]=useState({x:0,y:0});
 const [help,setHelp]=useState(false),[toast,setToast]=useState(''),[dimensions,setDimensions]=useState({});
 const gridRef=useRef(null),viewportRef=useRef(null),scrollPosition=useRef(0),importRef=useRef(null),queryRef=useRef(null),helpCloseRef=useRef(null),drag=useRef(null),toastTimer=useRef(null),previousHelpFocus=useRef(null),objectUrls=useRef([]);
 const [dragging,setDragging]=useState(false);
 const folderLabels={...window.PICSEE_FOLDERS,...customFolders,all:'所有照片',favorites:'个人收藏',recent:'最近查看'};
 const items=useMemo(()=>{
  let list=photos.filter(p=>folder==='all'||folder==='japan'&&!p.local||folder==='favorites'&&favorites.includes(p.id)||folder==='recent'&&recent.includes(p.id)||p.group===folder);
  const q=query.trim().toLowerCase();if(q)list=list.filter(p=>p.file.toLowerCase().includes(q));
  if(folder==='recent')return list.sort((a,b)=>recent.indexOf(a.id)-recent.indexOf(b.id));
  return [...list].sort((a,b)=>sortBy==='date'?b.date.localeCompare(a.date)||a.file.localeCompare(b.file):a.file.localeCompare(b.file,'zh-CN',{numeric:true}));
 },[photos,folder,favorites,recent,query,sortBy]);
 const current=items.find(p=>p.id===selected)||items[0],position=items.findIndex(p=>p.id===current?.id);
 useEffect(()=>{const media=matchMedia('(prefers-color-scheme: dark)');const changed=e=>setSystemDark(e.matches);media.addEventListener('change',changed);return()=>media.removeEventListener('change',changed)},[]);
 useEffect(()=>{document.documentElement.classList.remove('theme-light','theme-dark');document.documentElement.classList.add('theme-'+theme)},[theme]);
 useEffect(()=>{try{for(const [key,value] of Object.entries({'appearance':appearance,'names':showNames,'thumb-fit':thumbFit,'controls':alwaysControls,'learned':learned,'sidebar':sidebar,'sidebar-width':sidebarWidth,'cell-size':cellSize,'filmstrip':filmstrip}))localStorage.setItem('picsee-v2-'+key,JSON.stringify(value))}catch{}},[appearance,showNames,thumbFit,alwaysControls,learned,sidebar,sidebarWidth,cellSize,filmstrip]);
 useEffect(()=>{if(!viewer)return;const node=viewportRef.current;if(!node)return;const update=()=>setCanvasSize({width:node.clientWidth,height:node.clientHeight,pixelRatio:devicePixelRatio||1});update();const observer=new ResizeObserver(update);observer.observe(node);return()=>observer.disconnect()},[viewer]);
 useEffect(()=>{try{localStorage.setItem('picsee-prototype-favorites',JSON.stringify(favorites))}catch{}},[favorites]);
 useEffect(()=>()=>{objectUrls.current.forEach(URL.revokeObjectURL);clearTimeout(toastTimer.current)},[]);
 useEffect(()=>{if(!items.length){setViewer(false);setSelected(null)}else if(!items.some(p=>p.id===selected))setSelected(items[0].id)},[items,selected]);
 useEffect(()=>{setZoom(null);setPan({x:0,y:0});if(viewer&&current&&folder!=='recent')setRecent(list=>[current.id,...list.filter(id=>id!==current.id)])},[viewer,current?.id]);
 useEffect(()=>{if(viewer)requestAnimationFrame(()=>viewportRef.current?.focus({preventScroll:true}))},[viewer]);
 useLayoutEffect(()=>{if(!viewer&&gridRef.current){gridRef.current.scrollTop=scrollPosition.current;}},[viewer]);
 useEffect(()=>{if(viewer||!current)return;const node=document.querySelector(`[data-photo-id="${current.id}"]`);if(node&&document.activeElement?.closest('.photo-grid'))node.scrollIntoView({block:'nearest'});},[current?.id,viewer]);
 useEffect(()=>{if(!help)return;previousHelpFocus.current=document.activeElement;helpCloseRef.current?.focus();return()=>previousHelpFocus.current?.focus()},[help]);
 function notify(message){setToast(message);clearTimeout(toastTimer.current);toastTimer.current=setTimeout(()=>setToast(''),2200)}
 function openViewer(id=current?.id){if(!id)return;setLearned(true);scrollPosition.current=gridRef.current?.scrollTop||0;setSelected(id);setViewer(true);setHelp(false);setGridTools(null)}
 function closeViewer(){setViewer(false);requestAnimationFrame(()=>document.querySelector(`[data-photo-id="${selected}"]`)?.focus({preventScroll:true}))}
 function chooseFolder(next){scrollPosition.current=0;setFolder(next);setViewer(false);setQuery('');setHelp(false);requestAnimationFrame(()=>{if(gridRef.current)gridRef.current.scrollTop=0})}
 function navigate(delta){if(!items.length)return;const next=Math.max(0,Math.min(items.length-1,position+delta));setSelected(items[next].id);if(!viewer)requestAnimationFrame(()=>document.querySelector(`[data-photo-id="${items[next].id}"]`)?.focus())}
 function toggleFavorite(id=current?.id){if(!id)return;const liked=favorites.includes(id);setFavorites(list=>liked?list.filter(x=>x!==id):[...list,id]);notify(liked?'已从个人收藏移除':'已加入个人收藏')}
 useEffect(()=>{
  const onKey=e=>{
   if(help){if(e.key==='Escape'){e.preventDefault();setHelp(false)}if(e.key==='Tab'){e.preventDefault();helpCloseRef.current?.focus()}return;}
   if(e.defaultPrevented)return;
   if(gridTools&&e.key==='Escape'){e.preventDefault();setGridTools(null);return;}
   if((e.metaKey||e.ctrlKey)&&e.key.toLowerCase()==='f'){e.preventDefault();if(!viewer){setGridTools('search');requestAnimationFrame(()=>queryRef.current?.focus())}return;}
   if(e.metaKey||e.ctrlKey||e.altKey||e.target.closest('input,textarea,select,[contenteditable="true"]'))return;
   if(viewer&&['0','1','+','=','-'].includes(e.key)){e.preventDefault();setPan({x:0,y:0});if(e.key==='0')setZoom(null);else if(e.key==='1')setZoom(1);else changeZoom(e.key==='-'?-.1:.1);return;}
   if(e.key==='Escape'&&viewer){e.preventDefault();closeViewer();return;}
   if(e.key===' '&&!e.repeat){if(e.target.closest('button,a')&&!e.target.closest('.photo-cell'))return;e.preventDefault();viewer?closeViewer():openViewer();return;}
   if(e.key==='Enter'&&!viewer&&e.target.closest('.photo-cell')){e.preventDefault();openViewer();return;}
   if(['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(e.key)){
    if(!viewer&&!e.target.closest('.photo-grid'))return;
    e.preventDefault();let delta=e.key==='ArrowLeft'?-1:e.key==='ArrowRight'?1:0;
    if(!viewer&&(e.key==='ArrowDown'||e.key==='ArrowUp')){const columns=getComputedStyle(document.querySelector('.photo-grid')).gridTemplateColumns.split(' ').length;delta=columns*(e.key==='ArrowDown'?1:-1)}
    if(delta)navigate(delta);
   }
  };document.addEventListener('keydown',onKey);return()=>document.removeEventListener('keydown',onKey)
 },[items,position,viewer,current,selected,help,gridTools,zoom,canvasSize,dimensions]);
 useEffect(()=>{if(!gridTools)return;const outside=e=>{if(!e.target.closest('.grid-tools-panel,.grid-toolbar-tools'))setGridTools(null)};document.addEventListener('pointerdown',outside);return()=>document.removeEventListener('pointerdown',outside)},[gridTools]);
 function importImages(e){const files=Array.from(e.target.files||[]).filter(f=>f.type.startsWith('image/'));if(!files.length){notify('未找到可浏览的图片');e.target.value='';return;}
  const group='local-'+Date.now(),label=files[0].webkitRelativePath?.split('/')[0]||'导入的图片';
  const added=files.map((file,i)=>{const src=URL.createObjectURL(file);objectUrls.current.push(src);return{id:group+'-'+i,title:file.name,file:file.name,src,group,date:new Date(file.lastModified).toISOString().slice(0,10),bytes:file.size,local:true}});
  setCustomFolders(d=>({...d,[group]:label}));setPhotos(p=>[...p,...added]);setFolder(group);setQuery('');setSelected(added[0].id);setViewer(false);notify('已添加 '+files.length+' 张图片');e.target.value='';
 }
 function loaded(photo,e){const img=e.currentTarget;setDimensions(d=>d[photo.id]?.width===img.naturalWidth?d:{...d,[photo.id]:{width:img.naturalWidth,height:img.naturalHeight}})}
 function beginPan(e){if(actualZoom<=fitScale||e.button!==0)return;drag.current={x:e.clientX,y:e.clientY,origin:pan};e.currentTarget.setPointerCapture(e.pointerId);setDragging(true)}
 function movePan(e){if(!drag.current||!dim)return;const rect=viewportRef.current.getBoundingClientRect(),limitX=Math.max(0,(dim.width*actualZoom/pixelRatio-rect.width)/2),limitY=Math.max(0,(dim.height*actualZoom/pixelRatio-rect.height)/2);setPan({x:Math.max(-limitX,Math.min(limitX,drag.current.origin.x+e.clientX-drag.current.x)),y:Math.max(-limitY,Math.min(limitY,drag.current.origin.y+e.clientY-drag.current.y))})}
 function changeZoom(amount){setZoom(Math.max(.05,Math.min(8,actualZoom+amount)));setPan({x:0,y:0})}
 function resizeSidebar(e){e.preventDefault();const node=e.currentTarget;node.setPointerCapture(e.pointerId)}
 const sourceName=folderLabels[folder]||'文件夹',dim=dimensions[current?.id];
 const pixelRatio=canvasSize.pixelRatio||1;
 const fitScale=dim&&canvasSize.width?Math.min(1,Math.max(1,canvasSize.width-32)*pixelRatio/dim.width,Math.max(1,canvasSize.height-32)*pixelRatio/dim.height):1;
 const actualZoom=zoom===null?fitScale:zoom;
 const formatBytes=n=>n?(n/1024/1024).toFixed(2)+' MB':'示例图片';
 const count=g=>photos.filter(p=>g==='all'||g==='japan'&&!p.local||g==='favorites'&&favorites.includes(p.id)||g==='recent'&&recent.includes(p.id)||p.group===g).length;
 return <div className={'prototype-shell layout-exploration variant-'+variant+(viewer?' is-viewing':' is-grid')}  style={{'--picsee-sidebar-width':sidebarWidth+'px'}} data-screen-label={viewer?'大图浏览':'文件夹与缩略图网格'}>
  {!viewer&&<header className="titlebar">
   <div className="traffic" aria-hidden="true"><i></i><i></i><i></i></div>
   <div className="titlebar-middle" title={sourceName}><Icon name="folder" size={14}/><span>{sourceName}</span></div>
  </header>}
  <div className={'workspace '+(!sidebar?'sidebar-hidden':'')}>
   {sidebar&&<aside className="sidebar" aria-label="文件夹侧栏">
    <button className="sidebar-heading library-toggle" aria-expanded={libraryOpen} onClick={()=>setLibraryOpen(!libraryOpen)}>图库<Icon name={libraryOpen?'down':'right'} size={13}/></button>{libraryOpen&&<>
    <NavRow label="所有照片" icon={<Icon name="image" size={17}/>} count={count('all')} selected={folder==='all'} onClick={()=>chooseFolder('all')}/>
    <NavRow label="个人收藏" icon={<Icon name="heart" size={17}/>} count={count('favorites')} selected={folder==='favorites'} onClick={()=>chooseFolder('favorites')}/>
    <NavRow label="最近查看" icon={<Icon name="clock" size={17}/>} count={count('recent')} selected={folder==='recent'} onClick={()=>chooseFolder('recent')}/>
    </>}<div className="sidebar-heading folder-heading"><span>文件夹</span><button className="tiny-button" aria-label="添加文件夹" title="添加本地图片文件夹" onClick={()=>importRef.current.click()}><Icon name="plus" size={14}/></button></div>
    <NavRow label="日本 · 山海之间" icon={<Icon name="folderOpen" size={17}/>} count={count('japan')} selected={folder==='japan'} onClick={()=>chooseFolder('japan')}/>
    <div className="folder-children">{['forest','coast','street'].map(g=><NavRow key={g} label={folderLabels[g]} icon={<Icon name="folder" size={16}/>} count={count(g)} selected={folder===g} onClick={()=>chooseFolder(g)}/>)}</div>
    {Object.keys(customFolders).map(g=><NavRow key={g} label={customFolders[g]} icon={<Icon name="folder" size={17}/>} count={count(g)} selected={folder===g} onClick={()=>chooseFolder(g)}/>)}
    <button className="add-folder" onClick={()=>importRef.current.click()}><Icon name="plus" size={15}/><span>添加文件夹</span></button>
    <div className="sidebar-resizer" role="separator" tabIndex="0" aria-label="调整侧栏宽度" aria-orientation="vertical" aria-valuemin="160" aria-valuemax="320" aria-valuenow={sidebarWidth} onKeyDown={e=>{if(['ArrowLeft','ArrowRight'].includes(e.key)){e.preventDefault();setSidebarWidth(w=>Math.max(160,Math.min(320,w+(e.key==='ArrowRight'?10:-10))))}}} onPointerDown={resizeSidebar} onPointerMove={e=>{if(e.currentTarget.hasPointerCapture(e.pointerId))setSidebarWidth(Math.max(160,Math.min(Math.min(320,innerWidth-200),e.clientX)))}} onPointerUp={e=>e.currentTarget.releasePointerCapture(e.pointerId)}></div>
   </aside>}
   <main className="main-content">
    {!viewer?<>
     <div className="browser-body">
      <div className="grid-scroll" ref={gridRef} onScroll={e=>scrollPosition.current=e.currentTarget.scrollTop}>
       {items.length?<div className="photo-grid" role="listbox" aria-label="图片网格" style={{'--thumb-min':cellSize+'px'}}>{items.map(photo=><button type="button" key={photo.id} role="option" className={'photo-cell '+(current?.id===photo.id?'is-selected':'')} aria-selected={current?.id===photo.id} aria-label={photo.file} title={photo.file} data-photo-id={photo.id} tabIndex={current?.id===photo.id?0:-1} onFocus={()=>setSelected(photo.id)} onClick={()=>setSelected(photo.id)} onDoubleClick={()=>openViewer(photo.id)}>
        <div className={'thumbnail-wrap thumb-'+thumbFit}><Photo photo={photo} onLoad={e=>loaded(photo,e)}/>{favorites.includes(photo.id)&&<span className="favorite-mark"><Icon name="heart" size={13}/></span>}<span className="file-type">{photo.local?photo.file.split('.').pop().toUpperCase():'JPG'}</span></div>{showNames&&<div className="photo-name">{photo.file}</div>}
       </button>)}</div>:<div className="empty-state"><Icon name={query?'search':'image'} size={32}/><h2>{query?'没有匹配的图片':folder==='favorites'?'还没有收藏的图片':folder==='recent'?'还没有浏览记录':'文件夹里还没有图片'}</h2><p>{query?'试试其他名称，或清除搜索。':folder==='favorites'?'打开任意大图，点击收藏即可加入。':folder==='recent'?'选中一张图片，按 Space 开始浏览。':'添加本地文件夹，开始浏览你的图片。'}</p>{query&&<button className="text-button" onClick={()=>setQuery('')}>清除搜索</button>}</div>}
      </div>
      {inspector&&current&&<Inspector photo={current} dim={dim} favorite={favorites.includes(current.id)} onFavorite={()=>toggleFavorite()} onClose={()=>setInspector(false)} formatBytes={formatBytes}/>}
     </div>
    </>:current&&<PictureViewer variant={variant} current={current} items={items} position={position} navigate={navigate} sidebar={sidebar} setSidebar={setSidebar} inspector={inspector} setInspector={setInspector} filmstrip={filmstrip} setFilmstrip={setFilmstrip} zoom={zoom} actualZoom={actualZoom} imageDimensions={dim} pixelRatio={pixelRatio} alwaysControls={alwaysControls} setAlwaysControls={setAlwaysControls} appearance={appearance} setAppearance={setAppearance} changeZoom={changeZoom} resetZoom={()=>{setZoom(null);setPan({x:0,y:0})}} closeViewer={closeViewer} theme={theme} help={help} setHelp={setHelp} favorite={favorites.includes(current.id)} toggleFavorite={()=>toggleFavorite()} viewportRef={viewportRef} beginPan={beginPan} movePan={movePan} endPan={()=>{drag.current=null;setDragging(false)}} dragging={dragging} pan={pan} loaded={loaded} setSelected={setSelected} inspectorContent={inspector&&<Inspector photo={current} dim={dim} favorite={favorites.includes(current.id)} onFavorite={()=>toggleFavorite()} onClose={()=>setInspector(false)} formatBytes={formatBytes}/>} />}
   </main>
  </div>
  {!viewer&&<footer className="grid-bottom-bar" aria-label="网格底栏">
   <div className="grid-bottom-left"><IconButton label={sidebar?'隐藏侧栏':'显示侧栏'} pressed={sidebar} onClick={()=>setSidebar(!sidebar)}><Icon name="sidebar"/></IconButton><span className="toolbar-divider"></span><div className="grid-file-status"><span>{current?.file||sourceName}</span><span className="grid-folder-count">{items.length} 张图片</span></div></div>
   {!learned&&<div className="keyboard-hint"><Keycap>Space</Keycap><span>快速查看</span></div>}{query&&<button className="active-search" onClick={()=>setQuery('')} title="清除搜索，显示全部图片">搜索：{query}<Icon name="close" size={13}/></button>}
   <div className="grid-toolbar-tools"><IconButton label="搜索图片" pressed={gridTools==='search'||!!query} onClick={()=>{setGridTools(gridTools==='search'?null:'search');requestAnimationFrame(()=>queryRef.current?.focus())}}><Icon name="search" size={17}/></IconButton><IconButton label="图片排序" pressed={gridTools==='sort'} onClick={()=>setGridTools(gridTools==='sort'?null:'sort')}><Icon name="sort" size={17}/></IconButton><IconButton label={inspector?'隐藏图片信息':'显示图片信息'} pressed={inspector} onClick={()=>setInspector(!inspector)}><Icon name="info" size={17}/></IconButton><IconButton label="显示与外观" pressed={gridTools==='display'} onClick={()=>setGridTools(gridTools==='display'?null:'display')}><Icon name="grid" size={17}/></IconButton></div>
   {gridTools&&<section className="grid-tools-panel" aria-label={gridTools==='search'?'搜索面板':gridTools==='sort'?'排序面板':'显示面板'}>
    <header><strong>{gridTools==='search'?'搜索当前文件夹':gridTools==='sort'?'图片排序':'显示与外观'}</strong><IconButton label={'关闭'+(gridTools==='search'?'搜索':gridTools==='sort'?'排序':'显示')+'面板'} onClick={()=>setGridTools(null)}><Icon name="close" size={15}/></IconButton></header>
    {gridTools==='search'?<><label className="search"><Icon name="search" size={15}/><input ref={queryRef} type="search" placeholder="搜索文件名" aria-label="搜索当前文件夹" value={query} onChange={e=>setQuery(e.target.value)}/></label><div className="grid-search-caption"><span>{items.length} 个结果</span>{query&&<button className="text-button" onClick={()=>setQuery('')}>清除搜索</button>}</div></>:gridTools==='sort'?<label className="grid-sort-label">排序方式<select aria-label="排序方式" value={sortBy} onChange={e=>setSortBy(e.target.value)}><option value="name">名称排序</option><option value="date">日期从新到旧</option></select></label>:<>
     <label className="setting-row">缩略图大小<input type="range" min="140" max="280" step="10" aria-label="缩略图大小" value={cellSize} onChange={e=>setCellSize(+e.target.value)}/></label>
     <label className="setting-row">显示文件名<input type="checkbox" checked={showNames} onChange={e=>setShowNames(e.target.checked)}/></label>
     <label className="setting-row">缩略图<select aria-label="缩略图显示方式" value={thumbFit} onChange={e=>setThumbFit(e.target.value)}><option value="cover">填充裁剪</option><option value="contain">完整显示</option></select></label>
     <label className="setting-row">外观<select aria-label="外观" value={appearance} onChange={e=>setAppearance(e.target.value)}><option value="system">跟随系统</option><option value="light">浅色</option><option value="dark">深色</option></select></label>
     <label className="setting-row">始终显示大图工具<input type="checkbox" checked={alwaysControls} onChange={e=>setAlwaysControls(e.target.checked)}/></label>
     <button className="setting-help" onClick={()=>{setGridTools(null);setHelp(true)}}><Icon name="keyboard" size={16}/>键盘快捷键</button>
    </>}
   </section>}
  </footer>}
  <input ref={importRef} type="file" webkitdirectory="" multiple accept="image/*" hidden onChange={importImages}/>
  {toast&&<div className="toast" role="status"><Icon name="check" size={15}/>{toast}</div>}
  {help&&<div className="modal-scrim" onClick={()=>setHelp(false)}><section className="shortcut-modal" role="dialog" aria-modal="true" aria-labelledby="help-title" onClick={e=>e.stopPropagation()}><header><div><span className="eyebrow">PICSEE</span><h2 id="help-title">用键盘，顺手一点</h2></div><button className="tiny-button modal-close" ref={helpCloseRef} aria-label="关闭快捷键说明" onClick={()=>setHelp(false)}><Icon name="close"/></button></header><p>选中图片后，可以这样浏览。</p>{[['Space','打开 / 关闭大图'],['←  →','浏览上一张 / 下一张'],['↑  ↓','在网格中上下选择'],['Esc','返回网格，保留当前位置'],['Enter','打开选中的图片'],['0 / 1','适应窗口 / 1:1 原始尺寸'],['+ / −','放大 / 缩小图片']].map(([key,label])=><div className="shortcut-row" key={key}><span>{label}</span><Keycap>{key}</Keycap></div>)}<div className="help-foot">也可以双击缩略图打开大图。</div></section></div>}
 </div>
}
function Inspector({photo,dim,favorite,onFavorite,onClose,formatBytes}){const {IconButton}=window.PicseeUiSystem_bb8eab;return <aside className="inspector" aria-label="图片信息"><header><h2>图片信息</h2><IconButton label="关闭图片信息" onClick={onClose}><Icon name="close" size={16}/></IconButton></header><Photo photo={photo} className="inspector-preview"/><h3>{photo.file}</h3><p className="inspector-title">{photo.title}</p><dl><dt>尺寸</dt><dd>{dim?`${dim.width} × ${dim.height}`:'读取中'}</dd><dt>类型</dt><dd>{photo.local?'本地图片':'JPEG'}</dd><dt>日期</dt><dd>{photo.date}</dd><dt>大小</dt><dd>{formatBytes(photo.bytes)}</dd></dl><button className={'favorite-button '+(favorite?'liked':'')} onClick={onFavorite}><Icon name="heart" size={16}/>{favorite?'已加入个人收藏':'加入个人收藏'}</button>{photo.demo&&<p className="demo-note">演示照片 · 文件名与日期为示例<br/>照片来源见项目说明</p>}</aside>}
ReactDOM.createRoot(document.getElementById('root')).render(<App/>);
})();
