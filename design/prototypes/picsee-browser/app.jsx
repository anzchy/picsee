(function(){
const {useState,useEffect,useMemo,useRef,useLayoutEffect}=React;
const {IconButton,Keycap,NavRow}=window.PicseeUiSystem_bb8eab;
const Icon=window.PicseeIcon,Photo=window.PicseePhoto;
function saved(key,fallback){try{return JSON.parse(localStorage.getItem(key))??fallback}catch{return fallback}}
function App(){
 const [theme,setTheme]=useState(()=>document.documentElement.classList.contains('theme-dark')?'dark':'light');
 const [photos,setPhotos]=useState(window.PICSEE_PHOTOS);
 const [folder,setFolder]=useState('japan');
 const [customFolders,setCustomFolders]=useState({});
 const [selected,setSelected]=useState('temple');
 const [viewer,setViewer]=useState(false);
 const [sidebar,setSidebar]=useState(true),[inspector,setInspector]=useState(false);
 const [favorites,setFavorites]=useState(()=>saved('picsee-prototype-favorites',['alley','temple','shore']));
 const [recent,setRecent]=useState([]),[query,setQuery]=useState(''),[sortBy,setSortBy]=useState('name');
 const [cellSize,setCellSize]=useState(220),[zoom,setZoom]=useState(1),[pan,setPan]=useState({x:0,y:0});
 const [help,setHelp]=useState(false),[toast,setToast]=useState(''),[dimensions,setDimensions]=useState({});
 const gridRef=useRef(null),viewportRef=useRef(null),scrollPosition=useRef(0),importRef=useRef(null),queryRef=useRef(null),helpCloseRef=useRef(null),drag=useRef(null),toastTimer=useRef(null),previousHelpFocus=useRef(null),objectUrls=useRef([]);
 const [dragging,setDragging]=useState(false);
 const folderLabels={...window.PICSEE_FOLDERS,...customFolders,all:'所有照片',favorites:'个人收藏',recent:'最近查看'};
 const items=useMemo(()=>{
  let list=photos.filter(p=>folder==='all'||folder==='japan'&&!p.local||folder==='favorites'&&favorites.includes(p.id)||folder==='recent'&&recent.includes(p.id)||p.group===folder);
  const q=query.trim().toLowerCase();if(q)list=list.filter(p=>(p.file+' '+p.title).toLowerCase().includes(q));
  if(folder==='recent')return list.sort((a,b)=>recent.indexOf(a.id)-recent.indexOf(b.id));
  return [...list].sort((a,b)=>sortBy==='date'?b.date.localeCompare(a.date)||a.file.localeCompare(b.file):a.file.localeCompare(b.file,'zh-CN',{numeric:true}));
 },[photos,folder,favorites,recent,query,sortBy]);
 const current=items.find(p=>p.id===selected)||items[0],position=items.findIndex(p=>p.id===current?.id);
 useEffect(()=>{document.documentElement.classList.remove('theme-light','theme-dark');document.documentElement.classList.add('theme-'+theme);try{localStorage.setItem('picsee-prototype-theme',theme)}catch{}},[theme]);
 useEffect(()=>{try{localStorage.setItem('picsee-prototype-favorites',JSON.stringify(favorites))}catch{}},[favorites]);
 useEffect(()=>()=>{objectUrls.current.forEach(URL.revokeObjectURL);clearTimeout(toastTimer.current)},[]);
 useEffect(()=>{if(!items.length){setViewer(false);setSelected(null)}else if(!items.some(p=>p.id===selected))setSelected(items[0].id)},[items,selected]);
 useEffect(()=>{setZoom(1);setPan({x:0,y:0});if(viewer&&current&&folder!=='recent')setRecent(list=>[current.id,...list.filter(id=>id!==current.id)]);if(viewer)requestAnimationFrame(()=>viewportRef.current?.focus({preventScroll:true}))},[viewer,current?.id]);
 useLayoutEffect(()=>{if(!viewer&&gridRef.current){gridRef.current.scrollTop=scrollPosition.current;}},[viewer]);
 useEffect(()=>{if(viewer||!current)return;const node=document.querySelector(`[data-photo-id="${current.id}"]`);if(node&&document.activeElement?.closest('.photo-grid'))node.scrollIntoView({block:'nearest'});},[current?.id,viewer]);
 useEffect(()=>{if(!help)return;previousHelpFocus.current=document.activeElement;helpCloseRef.current?.focus();return()=>previousHelpFocus.current?.focus()},[help]);
 function notify(message){setToast(message);clearTimeout(toastTimer.current);toastTimer.current=setTimeout(()=>setToast(''),2200)}
 function openViewer(id=current?.id){if(!id)return;scrollPosition.current=gridRef.current?.scrollTop||0;setSelected(id);setViewer(true);setHelp(false)}
 function closeViewer(){setViewer(false);requestAnimationFrame(()=>document.querySelector(`[data-photo-id="${selected}"]`)?.focus({preventScroll:true}))}
 function chooseFolder(next){scrollPosition.current=0;setFolder(next);setViewer(false);setQuery('');setHelp(false);requestAnimationFrame(()=>{if(gridRef.current)gridRef.current.scrollTop=0})}
 function navigate(delta){if(!items.length)return;const next=Math.max(0,Math.min(items.length-1,position+delta));setSelected(items[next].id);if(!viewer)requestAnimationFrame(()=>document.querySelector(`[data-photo-id="${items[next].id}"]`)?.focus())}
 function toggleFavorite(id=current?.id){if(!id)return;const liked=favorites.includes(id);setFavorites(list=>liked?list.filter(x=>x!==id):[...list,id]);notify(liked?'已从个人收藏移除':'已加入个人收藏')}
 useEffect(()=>{
  const onKey=e=>{
   if(help){if(e.key==='Escape'){e.preventDefault();setHelp(false)}if(e.key==='Tab'){e.preventDefault();helpCloseRef.current?.focus()}return;}
   if(e.defaultPrevented)return;
   if((e.metaKey||e.ctrlKey)&&e.key.toLowerCase()==='f'){e.preventDefault();if(!viewer)queryRef.current?.focus();return;}
   if(e.metaKey||e.ctrlKey||e.altKey||e.target.closest('input,textarea,select,[contenteditable="true"]'))return;
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
 },[items,position,viewer,current,selected,help]);
 function importImages(e){const files=Array.from(e.target.files||[]).filter(f=>f.type.startsWith('image/'));if(!files.length){notify('未找到可浏览的图片');e.target.value='';return;}
  const group='local-'+Date.now(),label=files[0].webkitRelativePath?.split('/')[0]||'导入的图片';
  const added=files.map((file,i)=>{const src=URL.createObjectURL(file);objectUrls.current.push(src);return{id:group+'-'+i,title:file.name,file:file.name,src,group,date:new Date(file.lastModified).toISOString().slice(0,10),bytes:file.size,local:true}});
  setCustomFolders(d=>({...d,[group]:label}));setPhotos(p=>[...p,...added]);setFolder(group);setQuery('');setSelected(added[0].id);setViewer(false);notify('已添加 '+files.length+' 张图片');e.target.value='';
 }
 function loaded(photo,e){const img=e.currentTarget;setDimensions(d=>d[photo.id]?.width===img.naturalWidth?d:{...d,[photo.id]:{width:img.naturalWidth,height:img.naturalHeight}})}
 function beginPan(e){if(zoom<=1||e.button!==0)return;drag.current={x:e.clientX,y:e.clientY,origin:pan};e.currentTarget.setPointerCapture(e.pointerId);setDragging(true)}
 function movePan(e){if(!drag.current)return;const rect=e.currentTarget.getBoundingClientRect();setPan({x:Math.max(-rect.width*(zoom-1)/2,Math.min(rect.width*(zoom-1)/2,drag.current.origin.x+e.clientX-drag.current.x)),y:Math.max(-rect.height*(zoom-1)/2,Math.min(rect.height*(zoom-1)/2,drag.current.origin.y+e.clientY-drag.current.y))})}
 function changeZoom(amount){setZoom(value=>Math.max(1,Math.min(3,value+amount)));if(zoom+amount<=1)setPan({x:0,y:0})}
 const sourceName=folderLabels[folder]||'文件夹',dim=dimensions[current?.id];
 const formatBytes=n=>n?(n/1024/1024).toFixed(2)+' MB':'示例图片';
 const count=g=>photos.filter(p=>g==='all'||g==='japan'&&!p.local||g==='favorites'&&favorites.includes(p.id)||g==='recent'&&recent.includes(p.id)||p.group===g).length;
 return <div className="prototype-shell" data-screen-label={viewer?'大图浏览':'文件夹与缩略图网格'}>
  <header className="titlebar">
   <div className="traffic" aria-hidden="true"><i></i><i></i><i></i></div>
   <div className="app-brand"><span className="brand-mark"><Icon name="image" size={17}/></span>picsee</div>
   <div className="titlebar-middle"><Icon name="folder" size={14}/><span>{sourceName}</span></div>
   <div className="titlebar-actions"><div className="theme-switch" role="group" aria-label="外观主题"><IconButton label="浅色主题" pressed={theme==='light'} onClick={()=>setTheme('light')}><Icon name="sun" size={16}/></IconButton><IconButton label="深色主题" pressed={theme==='dark'} onClick={()=>setTheme('dark')}><Icon name="moon" size={16}/></IconButton></div><span className="separator"></span><IconButton label="键盘快捷键" pressed={help} onClick={()=>setHelp(true)}><Icon name="keyboard" size={17}/></IconButton></div>
  </header>
  <div className={'workspace '+(!sidebar?'sidebar-hidden':'')}>
   {sidebar&&<aside className="sidebar" aria-label="文件夹侧栏">
    <div className="sidebar-heading">图库</div>
    <NavRow label="所有照片" icon={<Icon name="image" size={17}/>} count={count('all')} selected={folder==='all'} onClick={()=>chooseFolder('all')}/>
    <NavRow label="个人收藏" icon={<Icon name="heart" size={17}/>} count={count('favorites')} selected={folder==='favorites'} onClick={()=>chooseFolder('favorites')}/>
    <NavRow label="最近查看" icon={<Icon name="clock" size={17}/>} count={count('recent')} selected={folder==='recent'} onClick={()=>chooseFolder('recent')}/>
    <div className="sidebar-heading folder-heading"><span>文件夹</span><button className="tiny-button" aria-label="添加文件夹" title="添加本地图片文件夹" onClick={()=>importRef.current.click()}><Icon name="plus" size={14}/></button></div>
    <NavRow label="日本 · 山海之间" icon={<Icon name="folderOpen" size={17}/>} count={count('japan')} selected={folder==='japan'} onClick={()=>chooseFolder('japan')}/>
    <div className="folder-children">{['forest','coast','street'].map(g=><NavRow key={g} label={folderLabels[g]} icon={<Icon name="folder" size={16}/>} count={count(g)} selected={folder===g} onClick={()=>chooseFolder(g)}/>)}</div>
    {Object.keys(customFolders).map(g=><NavRow key={g} label={customFolders[g]} icon={<Icon name="folder" size={17}/>} count={count(g)} selected={folder===g} onClick={()=>chooseFolder(g)}/>)}
    <button className="add-folder" onClick={()=>importRef.current.click()}><Icon name="plus" size={15}/><span>添加文件夹</span></button>
    <div className="sidebar-bottom"><div className="local-note"><Icon name="folder" size={15}/><span>本地图片，随手浏览</span></div><p>示例照片可直接体验；也可添加自己的图片。</p><span className="prototype-label">交互原型</span></div>
   </aside>}
   <main className="main-content">
    <div className="toolbar">
     <div className="toolbar-start"><IconButton label={sidebar?'隐藏侧栏':'显示侧栏'} pressed={sidebar} onClick={()=>setSidebar(!sidebar)}><Icon name="sidebar"/></IconButton><span className="toolbar-divider"></span>{viewer?<button className="back-button" onClick={closeViewer}><Icon name="left" size={16}/>返回网格</button>:<div className="breadcrumb"><span>图片</span><Icon name="right" size={12}/><strong>{sourceName}</strong></div>}</div>
     <div className="toolbar-end">{!viewer&&<label className="search"><Icon name="search" size={15}/><input ref={queryRef} type="search" placeholder="搜索当前文件夹" aria-label="搜索当前文件夹" value={query} onChange={e=>setQuery(e.target.value)}/><span>⌘ F</span></label>}<IconButton label={inspector?'隐藏图片信息':'显示图片信息'} pressed={inspector} onClick={()=>setInspector(!inspector)}><Icon name="info"/></IconButton></div>
    </div>
    {!viewer?<>
     <div className="collection-heading"><div><div className="eyebrow">{folder==='favorites'?'精选照片':folder==='recent'?'浏览记录':'文件夹'}</div><h1>{sourceName}</h1><p>{query?`找到 ${items.length} 张图片`:`${items.length} 张图片`}{folder==='japan'&&<><span className="dot">·</span>一次旅行，慢慢看</>}</p></div><label className="sort-control"><Icon name="sort" size={15}/><select aria-label="排序方式" value={sortBy} onChange={e=>setSortBy(e.target.value)}><option value="name">名称排序</option><option value="date">日期从新到旧</option></select></label></div>
     <div className="browser-body">
      <div className="grid-scroll" ref={gridRef} onScroll={e=>scrollPosition.current=e.currentTarget.scrollTop}>
       {items.length?<div className="photo-grid" role="listbox" aria-label="图片网格" style={{'--thumb-min':cellSize+'px'}}>{items.map(photo=><button type="button" key={photo.id} role="option" className={'photo-cell '+(current?.id===photo.id?'is-selected':'')} aria-selected={current?.id===photo.id} aria-label={photo.file+'，'+photo.title} data-photo-id={photo.id} tabIndex={current?.id===photo.id?0:-1} onFocus={()=>setSelected(photo.id)} onClick={()=>setSelected(photo.id)} onDoubleClick={()=>openViewer(photo.id)}>
        <div className="thumbnail-wrap"><Photo photo={photo} onLoad={e=>loaded(photo,e)}/>{favorites.includes(photo.id)&&<span className="favorite-mark"><Icon name="heart" size={13}/></span>}<span className="file-type">{photo.local?photo.file.split('.').pop().toUpperCase():'JPG'}</span>{current?.id===photo.id&&<span className="selected-check"><Icon name="check" size={12}/></span>}</div><div className="photo-name">{photo.file}</div><div className="photo-caption">{photo.title}</div>
       </button>)}</div>:<div className="empty-state"><Icon name={query?'search':'image'} size={32}/><h2>{query?'没有匹配的图片':folder==='favorites'?'还没有收藏的图片':folder==='recent'?'还没有浏览记录':'文件夹里还没有图片'}</h2><p>{query?'试试其他名称，或清除搜索。':folder==='favorites'?'打开任意大图，点击收藏即可加入。':folder==='recent'?'选中一张图片，按 Space 开始浏览。':'添加本地文件夹，开始浏览你的图片。'}</p>{query&&<button className="text-button" onClick={()=>setQuery('')}>清除搜索</button>}</div>}
      </div>
      {inspector&&current&&<Inspector photo={current} dim={dim} favorite={favorites.includes(current.id)} onFavorite={()=>toggleFavorite()} onClose={()=>setInspector(false)} formatBytes={formatBytes}/>}
     </div>
    </>:current&&<div className="viewer" data-testid="large-viewer">
     <div className="viewer-heading"><div><h1>{current.file}</h1><span>{current.title}</span></div><div className="viewer-tools"><IconButton label={favorites.includes(current.id)?'取消收藏':'收藏图片'} pressed={favorites.includes(current.id)} onClick={()=>toggleFavorite()}><Icon name="heart"/></IconButton><span className="toolbar-divider"></span><IconButton label="缩小图片" disabled={zoom===1} onClick={()=>changeZoom(-.25)}><Icon name="minus" size={16}/></IconButton><button className="zoom-label" onClick={()=>{setZoom(1);setPan({x:0,y:0})}} title="恢复适应窗口">{zoom===1?'适应窗口':Math.round(zoom*100)+'%'}</button><IconButton label="放大图片" disabled={zoom===3} onClick={()=>changeZoom(.25)}><Icon name="plus" size={16}/></IconButton><IconButton label="恢复适应窗口" onClick={()=>{setZoom(1);setPan({x:0,y:0})}}><Icon name="fit" size={17}/></IconButton></div></div>
     <div className="viewer-body"><div className="stage" ref={viewportRef} tabIndex={0} aria-label="大图画布，左右箭头翻图，Esc 返回" onPointerDown={beginPan} onPointerMove={movePan} onPointerUp={()=>{drag.current=null;setDragging(false)}} onPointerCancel={()=>{drag.current=null;setDragging(false)}} style={{cursor:zoom>1?dragging?'grabbing':'grab':'default'}}>
      <Photo photo={current} key={current.id} className="large-image" onLoad={e=>loaded(current,e)} style={{transform:`translate(${pan.x}px,${pan.y}px) scale(${zoom})`}}/>
      <button className="stage-arrow previous" aria-label="上一张图片" disabled={position<=0} onPointerDown={e=>e.stopPropagation()} onClick={()=>navigate(-1)}><Icon name="left" size={24}/></button><button className="stage-arrow next" aria-label="下一张图片" disabled={position>=items.length-1} onPointerDown={e=>e.stopPropagation()} onClick={()=>navigate(1)}><Icon name="right" size={24}/></button>
      <div className="stage-position">{position+1}<span> / {items.length}</span></div>
     </div>{inspector&&<Inspector photo={current} dim={dim} favorite={favorites.includes(current.id)} onFavorite={()=>toggleFavorite()} onClose={()=>setInspector(false)} formatBytes={formatBytes}/>}</div>
     <div className="filmstrip" aria-label="大图浏览缩略图条">{items.map(photo=><button key={photo.id} className={photo.id===current.id?'active':''} aria-label={'查看 '+photo.file} aria-current={photo.id===current.id?'true':undefined} onClick={()=>setSelected(photo.id)} ref={node=>{if(node&&photo.id===current.id)node.scrollIntoView({block:'nearest',inline:'nearest'})}}><Photo photo={photo}/></button>)}</div>
    </div>}
    <footer className="statusbar"><div className="file-status">{current?<><Icon name="image" size={14}/><span>{current.file}</span><span className="status-secondary">{dim?dim.width+' × '+dim.height:'JPEG'}</span></>:<span>{items.length} 张图片</span>}</div><div className="keyboard-hint">{viewer?<><Keycap>←</Keycap><Keycap>→</Keycap><span>翻图</span><Keycap>Esc</Keycap><span>返回</span></>:<><Keycap>Space</Keycap><span>快速查看</span></>}</div>{!viewer&&<div className="density-control"><Icon name="grid" size={13}/><input type="range" min="140" max="280" step="10" aria-label="缩略图大小" value={cellSize} onChange={e=>setCellSize(+e.target.value)}/><Icon name="grid" size={17}/></div>}</footer>
   </main>
  </div>
  <input ref={importRef} type="file" webkitdirectory="" multiple accept="image/*" hidden onChange={importImages}/>
  {toast&&<div className="toast" role="status"><Icon name="check" size={15}/>{toast}</div>}
  {help&&<div className="modal-scrim" onClick={()=>setHelp(false)}><section className="shortcut-modal" role="dialog" aria-modal="true" aria-labelledby="help-title" onClick={e=>e.stopPropagation()}><header><div><span className="eyebrow">PICSEE</span><h2 id="help-title">用键盘，顺手一点</h2></div><button className="tiny-button modal-close" ref={helpCloseRef} aria-label="关闭快捷键说明" onClick={()=>setHelp(false)}><Icon name="close"/></button></header><p>选中图片后，可以这样浏览。</p>{[['Space','打开 / 关闭大图'],['←  →','浏览上一张 / 下一张'],['↑  ↓','在网格中上下选择'],['Esc','返回网格，保留当前位置'],['Enter','打开选中的图片']].map(([key,label])=><div className="shortcut-row" key={key}><span>{label}</span><Keycap>{key}</Keycap></div>)}<div className="help-foot">也可以双击缩略图打开大图。</div></section></div>}
 </div>
}
function Inspector({photo,dim,favorite,onFavorite,onClose,formatBytes}){const {IconButton}=window.PicseeUiSystem_bb8eab;return <aside className="inspector" aria-label="图片信息"><header><h2>图片信息</h2><IconButton label="关闭图片信息" onClick={onClose}><Icon name="close" size={16}/></IconButton></header><Photo photo={photo} className="inspector-preview"/><h3>{photo.file}</h3><p className="inspector-title">{photo.title}</p><dl><dt>尺寸</dt><dd>{dim?`${dim.width} × ${dim.height}`:'读取中'}</dd><dt>类型</dt><dd>{photo.local?'本地图片':'JPEG'}</dd><dt>日期</dt><dd>{photo.date}</dd><dt>大小</dt><dd>{formatBytes(photo.bytes)}</dd></dl><button className={'favorite-button '+(favorite?'liked':'')} onClick={onFavorite}><Icon name="heart" size={16}/>{favorite?'已加入个人收藏':'加入个人收藏'}</button>{photo.demo&&<p className="demo-note">演示照片 · 文件名与日期为示例<br/>照片来源见项目说明</p>}</aside>}
ReactDOM.createRoot(document.getElementById('root')).render(<App/>);
})();
