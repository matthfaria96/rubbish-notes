ObjC.import('CoreGraphics');
function run(argv) {
  const p = $.CGPointMake(Number(argv[0]), Number(argv[1]));
  for (const t of [$.kCGEventMouseMoved, $.kCGEventLeftMouseDown, $.kCGEventLeftMouseUp]) {
    const e = $.CGEventCreateMouseEvent(null, t, p, $.kCGMouseButtonLeft);
    $.CGEventPost($.kCGHIDEventTap, e);
    delay(0.05);
  }
}
