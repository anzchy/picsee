window.PICSEE_PHOTOS = [
  {id:'alley', title:'灯火初上', file:'DSC_0341.jpg', group:'street', date:'2026-10-12', color:'warm'},
  {id:'lakeside', title:'湖畔鸟居', file:'DSC_0342.jpg', group:'coast', date:'2026-10-12', color:'green'},
  {id:'temple', title:'山寺之间', file:'DSC_0343.jpg', group:'forest', date:'2026-10-12', color:'green'},
  {id:'hillside', title:'山间人家', file:'DSC_0344.jpg', group:'forest', date:'2026-10-12', color:'green'},
  {id:'island', title:'海上朱红', file:'DSC_0345.jpg', group:'coast', date:'2026-10-13', color:'blue'},
  {id:'mountain', title:'雾起时分', file:'DSC_0346.jpg', group:'forest', date:'2026-10-13', color:'green'},
  {id:'lakehouse', title:'湖山有居', file:'DSC_0347.jpg', group:'forest', date:'2026-10-13', color:'green'},
  {id:'shore', title:'岸边的留白', file:'DSC_0348.jpg', group:'coast', date:'2026-10-14', color:'blue'},
  {id:'coast', title:'松影与潮汐', file:'DSC_0349.jpg', group:'coast', date:'2026-10-14', color:'blue'},
  {id:'morning', title:'清晨渡口', file:'DSC_0350.jpg', group:'coast', date:'2026-10-14', color:'blue'},
  {id:'blue', title:'一片深蓝', file:'DSC_0351.jpg', group:'coast', date:'2026-10-15', color:'blue'},
  {id:'gate', title:'海风经过', file:'DSC_0352.jpg', group:'coast', date:'2026-10-15', color:'blue'}
].map(photo=>({...photo,src:`assets/${photo.id}.jpg`,demo:true}));
window.PICSEE_FOLDERS = {japan:'日本 · 山海之间',forest:'山间与绿意',coast:'海岸与鸟居',street:'街巷'};
