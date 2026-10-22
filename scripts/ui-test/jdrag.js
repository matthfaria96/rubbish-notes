ObjC.import('CoreGraphics');
function run(argv) {
  const [x1, y1, x2, y2] = argv.map(Number);
  const post = (t, x, y) => { $.CGEventPost($.kCGHIDEventTap, $.CGEventCreateMouseEvent(null, t, $.CGPointMake(x, y), $.kCGMouseButtonLeft)); delay(0.03); };
  post($.kCGEventMouseMoved, x1, y1);
  post($.kCGEventLeftMouseDown, x1, y1);
  for (let i = 1; i <= 15; i++) post($.kCGEventLeftMouseDragged, x1 + (x2 - x1) * i / 15, y1 + (y2 - y1) * i / 15);
  delay(Number(argv[4] || 0.2));
  post($.kCGEventLeftMouseUp, x2, y2);
}
