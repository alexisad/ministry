import karax / [vstyles, karax, vdom, jstrutils]
import jsffi except `&`
import json, strformat
from math import PI
import src/util/types
import async_http_request
import jsbind


var console* {.importjs, nodecl.}: JsObject
var document* {.importjs, nodecl.}: JsObject
var H* {.importjs, nodecl.}: JsObject
var Kefir* {.importjs, nodecl.}: JsObject
proc jsonParse*(s: cstring): JsObject {.importjs: "JSON.parse(#)".}
proc jsonStringify*[T](o: T): cstring {.importcpp: "JSON.stringify(#)".}
proc jq*(selector: JsObject): JsObject {.importjs: "$$(#)".}
proc jqData*(obj: JsObject, hndlrs: cstring): JsObject {.importjs: "$$._data(#,#)".}


#{.emit: "function inherits(B,A) { function I() {}; I.prototype = A.prototype; B.prototype = new I(); B.prototype.constructor = B; return B;}".}
#proc inherits*(a: JsObject, b: JsObject): JsObject {.importjs: "inherits(#,#)".}
#proc getRemoteProvider(): JsObject {.importjs: "getCustomRemoteProvider()".}

#type
    #ContStreamEvts = object
        #inpSearchByName: JsObject
type
    PositionIndicator* = object
        size*: Natural
        marker*: JsObject
        canvas: JsObject

var
    currUser* = User()
    timeStamp*: string
    errMsg*: string
    isShowUsers* = false
    isShowNavMap* = false
    allUsers*: seq[User]
var pageYOffset {.importjs, nodecl.}: JsObject
var pageXOffset {.importjs, nodecl.}: JsObject
var engineTypes* = H.map.render.RenderEngine.EngineType
var curEngineType*: JsObject
var dwnloadedMaps*: seq[string]

proc  getElemCoords*(elem: JsObject): tuple[top, left: float] =
    let box = elem.getBoundingClientRect();

    result = (top: (box.top + pageYOffset).to(float), left: (box.left + pageXOffset).to(float))


template dbg*(x: untyped): untyped =
    when not defined(release):
        x

var isInternet* = true
var pIndicator*: PositionIndicator
#var window {.importjs, nodecl.}: JsObject
#var animMSec = (jsNew window.Date()).getMilliseconds().to(int)
var animCnt = 0
var opa = 0.00
var sopa = 1.00


proc sendRequest*(meth, url: string, body = "", headers: openarray[(string, string)] = @[]): JsObject =
    let hdrs = cast[seq[(cstring, cstring)]](headers)
    var rPrc =
        proc(emitter: JsObject): proc() =
            let oReq = newXMLHTTPRequest()
            var reqListener: proc ()
            reqListener = proc () =
                jsUnref(reqListener)
                #console.log("resp:", oReq.`type`.toJs, oReq.status.toJs, oReq.statusText.toJs, oReq.responseText.toJs)
                let stts = oReq.status
                let resp = Response((oReq.status, $oReq.statusText,  $oReq.responseText))
                if stts == 0 or stts in {100..199} or stts in {400..600}:
                    emitter.error(resp)
                else:    
                    emitter.emit(resp)
            jsRef(reqListener)
            oReq.addEventListener("load", reqListener)
            oReq.addEventListener("error", reqListener)
            #emitter.emit(1)
            oReq.open(meth.cstring, (if url != "": url & "&tst=" & timeStamp else: "").cstring)
            oReq.responseType = "text"
            for h in hdrs:
                oReq.setRequestHeader(h[0], h[1])
            if body.len == 0:
                oReq.send()
            else:
                oReq.send(body)
            #console.log("emitter:", emitter)
            result = proc() =
                async_http_request.abort(oReq)
    result = Kefir.stream(rPrc).take(1).takeErrors(1).toProperty()


proc parseResp*(bdy: string, T: typedesc): T =
    dbg: log("parseResp bdy:".cstring, bdy.cstring)
    result = bdy.parseJson.to(T)
    if $result.status == "loggedOut":
        currUser.token = ""
        isShowNavMap = false
        var elMap = jq("#map-container".toJs)[0]
        elMap.classList.remove(cstring"show-map")
        redraw()




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
    if curEngineType == engineTypes.P2D: #avoid tiles reload while indicator animated
        if not isInternet and not pIndicator.marker.getVisibility.to(bool):
            pIndicator.marker.setVisibility(true)
        if not isInternet:
            pIndicator.redrawIndCtx(1.00)
            return
    #let time = jsNew window.Date()
    #let op = time.getMilliseconds().to(int)
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

proc setPolyStyleByStat*(p: JsObject, stat: StreetStatus) =
    #let stStat = ord parseEnum[StreetStatus]($stat)
    let mClr =
        if stat == strNotStarted:
            "255, 0, 0"
        elif stat == strStarted:
            "0, 0, 255"
        else:
            "0, 255, 0"
    let opas =
        if curEngineType == engineTypes.P2D:
            "0.3"
        else:
            "0.5"
    p.setStyle(JsObject{
        strokeColor: fmt"rgba({mClr}, {opas})".cstring,
        #fillColor: cstring"rgba(" & mClr & ", 0.4)",
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