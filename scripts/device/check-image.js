// Decode PNG pixels through AppKit, rather than assuming a nonempty file is a capture.
function run(argv) {
  ObjC.import('AppKit');
  var bitmap = $.NSBitmapImageRep.imageRepWithContentsOfFile(argv[0]);
  if (!bitmap || !bitmap.pixelsWide || !bitmap.pixelsHigh) throw Error('black or empty image');
  var width = Number(bitmap.pixelsWide), height = Number(bitmap.pixelsHigh);
  for (var y = 0; y < height; y += Math.max(1, Math.floor(height / 32))) {
    for (var x = 0; x < width; x += Math.max(1, Math.floor(width / 32))) {
      var c = bitmap.colorAtXY(x, y).colorUsingColorSpace($.NSColorSpace.deviceRGBColorSpace);
      if (Number(c.alphaComponent) > 0.01 && Math.max(Number(c.redComponent), Number(c.greenComponent), Number(c.blueComponent)) > 0.01) {
        return 'PASS image pixels';
      }
    }
  }
  throw Error('black or empty image; check Screen Recording permission');
}
