(function(){
const {useState,useEffect,useRef}=React;
const {IconButton}=window.PicseeUiSystem_bb8eab;
const Icon=window.PicseeIcon,Photo=window.PicseePhoto;
function MoreIcon(){return <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="5" cy="12" r="1.5"/><circle cx="12" cy="12" r="1.5"/><circle cx="19" cy="12" r="1.5"/></svg>}
function StripIcon(){return <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" aria-hidden="true"><rect x="3" y="5" width="18" height="14" rx="2"/><path d="M3 15h18M8 15v4m8-4v4"/></svg>}
function PictureViewer(p){
 const {variant,current,items,position,navigate,sidebar,setSidebar,inspector,setInspector,filmstrip,setFilmstrip,zoom,changeZoom,resetZoom,closeViewer,theme,appearance,setAppearance,alwaysControls,setAlwaysControls,actualZoom,imageDimensions,pixelRatio,help,setHelp,favorite,toggleFavorite,viewportRef,beginPan,movePan,endPan,dragging,pan,loaded,setSelected,inspectorContent}=p;
 const [menuOpen,setMenuOpen]=useState(false),[awake,setAwake]=useState(true);
 const timeout=useRef(null),inControls=useRef(false),modality=useRef('pointer'),menuRef=useRef(null),menuButtonRef=useRef(null),layoutRef=useRef(null);
 const immersive=variant==='immersive';
 const stopTimer=()=>clearTimeout(timeout.current);
 function schedule(){stopTimer();if(!immersive||alwaysControls)return;timeout.current=setTimeout(()=>{
  const focused=layoutRef.current?.contains(document.activeElement)&&document.activeElement?.closest('[data-viewer-controls]');
  if(!inControls.current&&!menuOpen&&!filmstrip&&!help&&!inspector&&!(focused&&modality.current==='keyboard'))setAwake(false);
 },2500)}
 function reveal(){setAwake(true);schedule()}
 useEffect(()=>{setAwake(true);setMenuOpen(false);schedule();return stopTimer},[variant]);
 useEffect(()=>{if(menuOpen||filmstrip||help||inspector||alwaysControls){setAwake(true);stopTimer()}else{inControls.current=false;schedule();}return stopTimer},[menuOpen,filmstrip,help,inspector,alwaysControls,variant]);
 useEffect(()=>{
  const key=e=>{modality.current='keyboard';if(e.key==='Tab'){if(immersive&&!awake){e.preventDefault();setAwake(true);requestAnimationFrame(()=>layoutRef.current?.querySelector('.leading-pod button')?.focus())}else setAwake(true);stopTimer()}}
  const pointer=()=>{modality.current='pointer'};
  document.addEventListener('keydown',key);document.addEventListener('pointerdown',pointer);
  return()=>{document.removeEventListener('keydown',key);document.removeEventListener('pointerdown',pointer)};
 },[immersive,awake]);
 useEffect(()=>{
  if(!menuOpen)return;
  menuRef.current?.querySelector('button,input,select')?.focus();
  const outside=e=>{if(!e.target.closest('.viewer-more-menu,.more-button-wrap'))setMenuOpen(false)};
  const keyboard=e=>{
   if(e.key==='Escape'){e.preventDefault();e.stopImmediatePropagation();setMenuOpen(false);menuButtonRef.current?.querySelector('button,input,select')?.focus()}
   if(e.key==='Tab'){
    const buttons=[...menuRef.current.querySelectorAll('button,input,select')],idx=buttons.indexOf(document.activeElement);
    if(e.shiftKey&&idx===0||!e.shiftKey&&idx===buttons.length-1){e.preventDefault();setMenuOpen(false);menuButtonRef.current?.querySelector('button,input,select')?.focus()}
   }
  };
  document.addEventListener('pointerdown',outside);document.addEventListener('keydown',keyboard,true);
  return()=>{document.removeEventListener('pointerdown',outside);document.removeEventListener('keydown',keyboard,true)}
 },[menuOpen]);
 useEffect(()=>{
  if(!layoutRef.current)return;
  const observer=new ResizeObserver(()=>{const box=viewportRef.current?.getBoundingClientRect(),shell=layoutRef.current.closest('.workspace')?.getBoundingClientRect();if(box&&shell)window.dispatchEvent(new CustomEvent('picsee-canvas-metrics',{detail:{height:Math.round(box.height),width:Math.round(box.width),percentage:Math.round(box.height/shell.height*100)}}))});
  observer.observe(layoutRef.current);return()=>observer.disconnect()
 },[variant,sidebar,inspector]);
 function trackingEnter(){inControls.current=true;reveal();stopTimer()}
 function trackingLeave(){inControls.current=false;schedule()}
 const tracking={onPointerEnter:trackingEnter,onPointerLeave:trackingLeave,onFocusCapture:()=>{if(modality.current==='keyboard'){setAwake(true);stopTimer()}},onBlurCapture:()=>schedule()};
 const Zoom=()=> <div className="zoom-pod" data-viewer-controls="zoom" {...tracking} onPointerDown={e=>e.stopPropagation()}>
  <IconButton label="缩小图片" disabled={actualZoom<=.05} onClick={()=>changeZoom(-.25)}><Icon name="minus" size={16}/></IconButton>
  <select className="zoom-label" aria-label="缩放模式" value={zoom===null?'fit':zoom===1?'actual':'custom'} onChange={e=>{if(e.target.value==='fit')resetZoom();else if(e.target.value==='actual')changeZoom(1-actualZoom)}}><option value="fit">适应窗口</option><option value="actual">1:1 · 100%</option>{zoom!==null&&zoom!==1&&<option value="custom">{Math.round(actualZoom*100)}%</option>}</select>
  <IconButton label="放大图片" disabled={actualZoom>=8} onClick={()=>changeZoom(.25)}><Icon name="plus" size={16}/></IconButton>
  
 </div>;
 const Navigation=()=> <div className="navigation-pod" data-viewer-controls="navigation" {...tracking}>
  <IconButton label="上一张图片" disabled={position===0} onClick={()=>navigate(-1)}><Icon name="left" size={17}/></IconButton>
  <div className="viewer-file-label"><strong>{current.file}</strong><span>{position+1} / {items.length}</span></div>
  <IconButton label="下一张图片" disabled={position===items.length-1} onClick={()=>navigate(1)}><Icon name="right" size={17}/></IconButton>
 </div>;
 const Leading=()=> <div className="leading-pod" data-viewer-controls="leading" {...tracking}>
  <IconButton label={sidebar?'隐藏侧栏':'显示侧栏'} pressed={sidebar} onClick={()=>setSidebar(!sidebar)}><Icon name="sidebar" size={18}/></IconButton>
  <IconButton label="返回网格" onClick={closeViewer}><Icon name="grid" size={17}/></IconButton>
  <span className="more-button-wrap" ref={menuButtonRef}><IconButton label="更多浏览操作" pressed={menuOpen} onClick={()=>setMenuOpen(!menuOpen)}><MoreIcon/></IconButton></span>
 </div>;
 return <div ref={layoutRef} className={'picture-viewer '+(awake?'chrome-awake':'chrome-asleep')+(filmstrip?' strip-open':'')} data-testid="large-viewer" data-variant={variant}>
  <div className="picture-surface">
   <div className="picture-stage" ref={viewportRef} tabIndex="0" aria-label="大图画布，左右箭头翻图，Esc 返回" onPointerDown={beginPan} onPointerMove={e=>{movePan(e);if(immersive){const box=e.currentTarget.getBoundingClientRect();if(e.clientY>box.bottom-90||e.clientY<box.top+38)reveal();else if(awake&&!inControls.current)schedule()}}} onPointerUp={endPan} onPointerCancel={endPan} style={{cursor:zoom!==null?(dragging?'grabbing':'grab'):'default'}}>
    <Photo photo={current} key={current.id} className="large-image" onLoad={e=>loaded(current,e)} style={{width:imageDimensions?imageDimensions.width*actualZoom/pixelRatio:undefined,height:imageDimensions?imageDimensions.height*actualZoom/pixelRatio:undefined,transform:`translate(${pan.x}px,${pan.y}px)`}}/>
    <div className="native-window-hint" aria-hidden="true"><div className="traffic"><i></i><i></i><i></i></div></div>
    <div className="viewer-floating-controls" onPointerDown={e=>e.stopPropagation()} inert={immersive&&!awake?'':undefined}>
     {Zoom()}
     {Leading()}{Navigation()}
     {menuOpen&&<div ref={menuRef} className="viewer-more-menu" data-viewer-controls="menu" role="group" aria-label="更多浏览操作菜单" {...tracking}>
      <div className="menu-file-name">{current.file}<span>{current.title}</span></div>
      <button onClick={()=>{toggleFavorite();setMenuOpen(false)}}><Icon name="heart" size={16}/>{favorite?'取消收藏':'收藏图片'}</button>
      <button onClick={()=>{setFilmstrip(!filmstrip);setMenuOpen(false)}}><StripIcon/>{filmstrip?'隐藏缩略图条':'显示缩略图条'}</button>
      <button onClick={()=>{setInspector(!inspector);setMenuOpen(false)}}><Icon name="info" size={16}/>{inspector?'隐藏图片信息':'显示图片信息'}</button>
      <div className="menu-separator"></div>
      <label className="setting-row">外观<select aria-label="外观" value={appearance} onChange={e=>setAppearance(e.target.value)}><option value="system">跟随系统</option><option value="light">浅色</option><option value="dark">深色</option></select></label>
      <label className="setting-row">始终显示工具<input type="checkbox" checked={alwaysControls} onChange={e=>setAlwaysControls(e.target.checked)}/></label>
      <button onClick={()=>{setHelp(true);setMenuOpen(false)}}><Icon name="keyboard" size={16}/>键盘快捷键</button>
     </div>}
    </div>
    {filmstrip&&<div className="picture-filmstrip" data-viewer-controls="filmstrip" aria-label="大图浏览缩略图条" {...tracking} onPointerDown={e=>e.stopPropagation()}>{items.map(photo=><button key={photo.id} aria-label={'查看 '+photo.file} aria-current={photo.id===current.id?'true':undefined} className={photo.id===current.id?'active':''} onClick={()=>setSelected(photo.id)} ref={node=>{if(node&&photo.id===current.id)node.scrollIntoView({block:'nearest',inline:'nearest'})}}><Photo photo={photo}/></button>)}</div>}
   </div>
   {inspectorContent}
  </div>
 </div>
}
window.PicseeViewerLayouts={PictureViewer};
})();
