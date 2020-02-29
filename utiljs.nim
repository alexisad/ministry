import jsffi, strutils
from math import PI
import src/util/types

var console* {.importjs, nodecl.}: JsObject
var document* {.importjs, nodecl.}: JsObject
var H* {.importjs, nodecl.}: JsObject

#{.emit: "function inherits(B,A) { function I() {}; I.prototype = A.prototype; B.prototype = new I(); B.prototype.constructor = B; return B;}".}
#proc inherits*(a: JsObject, b: JsObject): JsObject {.importjs: "inherits(#,#)".}
proc getRemoteProvider(): JsObject {.importjs: "getCustomRemoteProvider()".}

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
var engineTypes* = H.map.render.RenderEngine.EngineType
var curEngineType*: int

proc  getElemCoords*(elem: JsObject): tuple[top, left: float] =
    let box = elem.getBoundingClientRect();

    result = (top: (box.top + pageYOffset).to(float), left: (box.left + pageXOffset).to(float))


template dbg*(x: untyped): untyped =
    when not defined(release):
        x

var isInternet* = true
var pIndicator*: PositionIndicator
var window {.importjs, nodecl.}: JsObject
var animMSec = (jsNew window.Date()).getMilliseconds().to(int)
var animCnt = 0
var opa = 0.00
var sopa = 1.00

proc redrawIndCtx(pIndicator: PositionIndicator, opa: float) =
    var ctx = pIndicator.canvas.getContext(cstring"2d")
    let size = pIndicator.size
    ctx.clearRect(0, 0, size, size)
    ctx.fillStyle = cstring("rgba(255, 0, 0, " & $opa & ")")
    #ctx.fillStyle = cstring("rgba(255, 0, 0, 1)")
    ctx.strokeStyle = cstring"white"
    ctx.beginPath()
    ctx.arc(size/2, size/2, size/2-1, 0, 2 * PI)
    ctx.fill()
    ctx.stroke()


proc drawInd*() =
    if curEngineType == engineTypes.P2D.to(int): #avoid tiles reload while indicator animated
        if not isInternet and not pIndicator.marker.getVisibility.to(bool):
            pIndicator.marker.setVisibility(true)
        if not isInternet:
            pIndicator.redrawIndCtx(1.00)
            return
    let time = jsNew window.Date()
    let op = time.getMilliseconds().to(int)
    #dbg: console.log("op-animMSec:", op-animMSec)
    if animCnt == 8:
        animCnt = 0
        #animMSec = op
        pIndicator.marker.setVisibility(false)
        pIndicator.redrawIndCtx(opa)
        pIndicator.marker.setVisibility(true)
        #dbg: console.log("opa", opa)
        if opa > 1 and sopa == 1:
            sopa = -1.00 #begin reverse opacity   
        elif opa < 0 and sopa == -1:
            sopa = 1.00
        opa = opa + sopa * 0.25
    inc animCnt
    #window.requestAnimationFrame(drawInd)
    #drawInd()
        

proc newPositionIndicator*(size: Natural): PositionIndicator =
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
            icon: jsNew H.map.Icon(canvas),
            volatility: true
        }
    )

proc setPolyStyleByStat*(p: JsObject, stat: cstring) =
    let stStat = ord parseEnum[StreetStatus]($stat)
    let mClr =
        if stStat == 0:
            "255, 0, 0"
        elif stStat == 1:
            "0, 0, 255"
        else:
            "0, 255, 0"
    p.setStyle(JsObject{
        strokeColor: cstring"rgba(" & mClr & ", 0.2)",
        fillColor: cstring"rgba(" & mClr & ", 0.4)",
        lineWidth: 10
    })

#[
var rProv = getRemoteProvider()
rProv.it.prototype.requestInternal = toJs(proc (x, y, level: int, onSuccess: proc(img: JsObject): JsObject, onError: proc(): JsObject): JsObject =
    dbg: console.log("x, y, level:", x, y, level)
)
dbg: console.log("inherits:", rProv.it.prototype)
var rProvObj = jsNew rProv.it
dbg: console.log("inherits:", rProvObj)
var custBaseLayer* = jsNew H.map.layer.TileLayer(rProvObj)
]#