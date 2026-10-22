ObjC.import('CoreGraphics');
ObjC.import('Foundation');
function run(){
  var list=ObjC.castRefToObject($.CGWindowListCopyWindowInfo($.kCGWindowListOptionOnScreenOnly,0));
  var out=[];
  for(var i=0;i<list.count;i++){var w=list.objectAtIndex(i);
    var owner=ObjC.unwrap(w.objectForKey('kCGWindowOwnerName'));
    if(owner==='mdpro'||owner==='tauri-app'){var b=w.objectForKey('kCGWindowBounds');
      out.push([ObjC.unwrap(w.objectForKey('kCGWindowNumber')),owner,ObjC.unwrap(w.objectForKey('kCGWindowLayer')),ObjC.unwrap(b.objectForKey('Width')),ObjC.unwrap(b.objectForKey('Height')),ObjC.unwrap(w.objectForKey('kCGWindowName'))].join(' '));}}
  return out.join('\n');
}
