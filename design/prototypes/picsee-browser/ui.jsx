(function(){
function Icon({name,size=18}) {
 const paths={
  folder:<><path d="M3 7V5a2 2 0 0 1 2-2h5l2 3h7a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2Z"/></>,
  folderOpen:<><path d="M3 9V5a2 2 0 0 1 2-2h5l2 3h7a2 2 0 0 1 2 2v2"/><path d="M3 10h17a1 1 0 0 1 1 1.3l-2 8a2 2 0 0 1-2 1.7H5a2 2 0 0 1-2-2Z"/></>,
  grid:<><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/></>,
  image:<><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3-3a2 2 0 0 0-3 0L6 21"/></>,
  heart:<path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 21l8.8-8.6a5.5 5.5 0 0 0 0-7.8Z"/>,
  clock:<><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></>,
  sun:<><circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1.5 1.5m11 11L19 19M5 19l1.5-1.5m11-11L19 5"/></>,
  moon:<path d="M20 14.5A8.5 8.5 0 0 1 9.5 4 8.5 8.5 0 1 0 20 14.5Z"/>,
  left:<path d="m14 6-6 6 6 6"/>,right:<path d="m10 6 6 6-6 6"/>,down:<path d="m7 10 5 5 5-5"/>,
  search:<><circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/></>,
  sidebar:<><rect x="3" y="3" width="18" height="18" rx="2"/><path d="M9 3v18"/></>,
  info:<><circle cx="12" cy="12" r="9"/><path d="M12 11v6m0-10h.01"/></>,
  plus:<path d="M12 5v14M5 12h14"/>,minus:<path d="M5 12h14"/>,
  fit:<><path d="M8 3H3v5m13-5h5v5M3 16v5h5m13-5v5h-5"/><rect x="7" y="7" width="10" height="10" rx="1"/></>,
  close:<path d="m6 6 12 12M6 18 18 6"/>,check:<path d="m5 12 4 4L19 6"/>,
  sort:<><path d="M8 4v16m-4-4 4 4 4-4M15 5h6m-6 5h4m-4 5h2"/></>,
  keyboard:<><rect x="2" y="5" width="20" height="14" rx="2"/><path d="M6 9h.01M10 9h.01M14 9h.01M18 9h.01M6 13h.01M10 13h.01M14 13h.01M18 13h.01M7 16h10"/></>,
  expand:<><path d="M8 3H3v5m13-5h5v5M3 16v5h5m13-5v5h-5"/></>,
  camera:<><path d="M4 7h4l2-3h4l2 3h4a1 1 0 0 1 1 1v11H3V8a1 1 0 0 1 1-1Z"/><circle cx="12" cy="13" r="4"/></>,
 };
 return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{paths[name]||paths.image}</svg>;
}
function Photo({photo,className='',style,onLoad}){
 const [broken,setBroken]=React.useState(false);
 React.useEffect(()=>setBroken(false),[photo.src]);
 return broken?<div className={'image-failure '+className}><Icon name="image"/><span>图片无法加载</span></div>:<img className={className} src={photo.src} alt={photo.title||photo.file} style={style} onLoad={onLoad} onError={()=>setBroken(true)} draggable="false"/>;
}
Object.assign(window,{PicseeIcon:Icon,PicseePhoto:Photo});
})();
