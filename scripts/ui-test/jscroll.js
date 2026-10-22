ObjC.import('CoreGraphics');
function run(argv) {
  $.CGEventPost($.kCGHIDEventTap, $.CGEventCreateMouseEvent(null, $.kCGEventMouseMoved, $.CGPointMake(Number(argv[0]), Number(argv[1])), 0));
  for (let i = 0; i < Number(argv[2]); i++) { $.CGEventPost($.kCGHIDEventTap, $.CGEventCreateScrollWheelEvent(null, 1, 1, Number(argv[3]))); delay(0.03); }
}
