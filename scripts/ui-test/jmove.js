ObjC.import('CoreGraphics');
function run(argv) { $.CGEventPost($.kCGHIDEventTap, $.CGEventCreateMouseEvent(null, $.kCGEventMouseMoved, $.CGPointMake(Number(argv[0]), Number(argv[1])), $.kCGMouseButtonLeft)); }
