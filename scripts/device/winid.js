// Shared PID selection is exercised with node --test; runtime uses CGWindowList.
function selectWindows(windows, pid) {
  return windows.filter(function(w) {
    return Number(w.kCGWindowOwnerPID) === Number(pid) && Number(w.kCGWindowLayer) === 0;
  });
}
if (typeof module !== 'undefined') module.exports = {selectWindows: selectWindows};
function run(argv) {
  if (argv.length !== 1 || !/^\d+$/.test(argv[0]) || Number(argv[0]) <= 1) throw Error('usage: winid.js <pid>');
  ObjC.import('CoreGraphics');
  ObjC.import('Foundation');
  var list = ObjC.castRefToObject($.CGWindowListCopyWindowInfo($.kCGWindowListOptionOnScreenOnly, 0));
  var windows = ObjC.deepUnwrap(list);
  return selectWindows(windows, argv[0]).map(function(w) {
    return [w.kCGWindowNumber, w.kCGWindowOwnerPID, w.kCGWindowLayer,
      w.kCGWindowBounds.Width, w.kCGWindowBounds.Height, w.kCGWindowName || ''].join('\t');
  }).join('\n');
}
