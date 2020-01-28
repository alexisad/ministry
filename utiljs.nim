import jsffi
from math import PI

type
    ContStreamEvts = object
        inpSearchByName: JsObject
type
    PositionIndicator* = object
        size*: Natural
        marker*: JsObject
        canvas: JsObject

var pageYOffset {.importjs, nodecl.}: JsObject
var pageXOffset {.importjs, nodecl.}: JsObject

proc  getElemCoords*(elem: JsObject): tuple[top, left: float] =
    let box = elem.getBoundingClientRect();

    result = (top: (box.top + pageYOffset).to(float), left: (box.left + pageXOffset).to(float))


template dbg*(x: untyped): untyped =
    when not defined(release):
        x


proc draww*(that: JsObject) =
    let size = that.size.to(int)
    var window {.importjs, nodecl.}: JsObject
    let time = jsNew window.Date()
    var ctx = that.canvas.getContext(cstring"2d")
    ctx.clearRect(0, 0, size, size)
    let op = time.getMilliseconds().to(int)/1000
    #ctx.fillStyle = cstring("rgba(255, 0, 0, " & $op & ")")
    ctx.fillStyle = cstring("rgba(255, 0, 0, 1)")
    ctx.strokeStyle = cstring"white"
    ctx.beginPath()
    ctx.arc(size/2, size/2, size/2-1, 0, 2 * PI)
    ctx.fill()
    ctx.stroke()
    window.requestAnimationFrame(draww)
        

proc newPositionIndicator*(size: Natural): PositionIndicator =
    var document {.importjs, nodecl.}: JsObject
    var H {.importjs, nodecl.}: JsObject
    var console {.importjs, nodecl.}: JsObject
    result.size = size
    result.canvas = document.createElement(cstring"canvas")
    result.canvas.width = size
    result.canvas.height = size
    dbg: console.log("canvas: ", result.canvas)
    let canvas = result.canvas
    #document.body.appendChild(canvas)
    result.marker = jsNew H.map.Marker(
        JsObject{lat: 0, lng: 0},
        JsObject{
            icon: jsNew H.map.Icon(canvas)
        }
    )
    #result.draw()


