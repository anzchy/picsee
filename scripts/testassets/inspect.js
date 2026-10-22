// Optional independent macOS ImageIO inspection; reads metadata, never allocates declared pixels.
function run(argv) {
  ObjC.import('Foundation');
  ObjC.import('ImageIO');
  ObjC.import('CoreGraphics');
  var source = $.CGImageSourceCreateWithURL($.NSURL.fileURLWithPath(argv[0]), null);
  if (argv[1] === 'truncated') {
    // Only this known tiny fixture enters bounded decode; never the oversize header.
    var partial = source ? $.CGImageSourceCreateThumbnailAtIndex(source, 0,
      $({kCGImageSourceCreateThumbnailFromImageAlways:true,
         kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:64})) : null;
    if (partial && (Number($.CGImageGetWidth(partial)) > 64 || Number($.CGImageGetHeight(partial)) > 64))
      throw Error('truncated thumbnail exceeded bound');
    return JSON.stringify({truncated:partial ? 'partial' : 'failed'});
  }
  if (!source) throw Error('ImageIO cannot read source');
  var p = ObjC.deepUnwrap(ObjC.castRefToObject($.CGImageSourceCopyPropertiesAtIndex(source, 0, null)));
  var result = {width:p.PixelWidth, height:p.PixelHeight, orientation:p.Orientation || 1,
    hasExif:!!p['{Exif}'], hasAlpha:!!p.HasAlpha};
  if (argv[1] === 'oriented-pixels') {
    var options = $({kCGImageSourceCreateThumbnailFromImageAlways:true,
      kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:128});
    var image = $.CGImageSourceCreateThumbnailAtIndex(source,0,options);
    result.displayWidth = Number($.CGImageGetWidth(image));
    result.displayHeight = Number($.CGImageGetHeight(image));
    result.pixels = ObjC.unwrap(ObjC.castRefToObject($.CGDataProviderCopyData($.CGImageGetDataProvider(image))).base64EncodedStringWithOptions(0));
  }
  return JSON.stringify(result);
}
