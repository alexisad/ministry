import jsffi

var pageYOffset {.importjs, nodecl.}: JsObject
var pageXOffset {.importjs, nodecl.}: JsObject

proc  getElemCoords*(elem: JsObject): tuple[top, left: float] =
    let box = elem.getBoundingClientRect();

    result = (top: (box.top + pageYOffset).to(float), left: (box.left + pageXOffset).to(float))
