# nim -o:public/js/ministry.js js --oldgensym:on --opt:speed -d:release ministryjs.nim
# nim -o:public/js/ministry.js js --debuginfo:on --oldgensym:on ministryjs.nim
# browser-sync start --proxy "http://127.0.0.1:5000" --files "public/js/*.js"

include karax / prelude
import jsffi except `&`
import jsbind, async_http_request, asyncjs
from sugar import `=>`, `->`
import src/util/types
import strformat, strutils
import utiljs


var console {.importjs, nodecl.}: JsObject
var window {.importjs, nodecl.}: JsObject
var screen {.importjs, nodecl.}: JsObject
proc jq(selector: JsObject): JsObject {.importjs: "$$(#)".}
var JSON {.importjs, nodecl.}: JsObject
var Kefir {.importjs, nodecl.}: JsObject
var H {.importjs, nodecl.}: JsObject
var token = $jq("#token".toJs).val().to(cstring)
var currUser = User(token: token)
var currProcess: CSectorProcess
var allSectProc: seq[CSectorProcess]
var spinnerOn = false
var isShowNavMap = false
var map: JsObject
var sectStreetGrp = jsNew H.map.Group()

when false:
    var kPrc = proc(emitter: JsObject): proc() =
                result = proc() = discard
                console.log("emitter:", emitter)
                emitter.emit(1)
    var stm = Kefir.stream(kPrc)
    stm.log()

proc sendRequest(meth, url: string, body = "", headers: openarray[(string, string)] = @[]): JsObject =
    let hdrs = cast[seq[(string, string)]](headers)
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
                oReq.open(meth, url)
                oReq.responseType = "text"
                for h in hdrs:
                    oReq.setRequestHeader(h[0], h[1])
                if body.len == 0:
                    oReq.send()
                else:
                    oReq.send(body)
                #console.log("emitter:", emitter)
                result = proc() =
                    oReq.abort()
                
    result = Kefir.stream(rPrc).take(1).takeErrors(1).toProperty()
#login("", "").log()
#sendRequest*(meth, url, body: string, headers: openarray[(string, string)], handler: proc(body: string))
var hndl: Handler =
            proc (data: Response) =
                console.log("resp:", data.body.toJs)


when false:
    sendRequest(
            "POST",
            "/login",
            "email=sadovoyalexander%40yahoo.de&pass=111",
            @[("Content-Type", "application/x-www-form-urlencoded")],
            #(b: string) => (console.log("cb:: ", b))
            proc (data: Response) =
                let result = 
                    if data.statusCode == 404:
                        StatusResp[TokenResp](status: false)
                    else:
                        StatusResp[TokenResp](status: true, resp: JSON.parse(data.body).to(TokenResp))
                console.log("resp body:", data.body)
                console.log("resp:", data.toJs, data.statusCode.toJs, data.status.toJs, result)
    )


proc login(btnClass: kstring): proc() =
    result = proc() =
        spinnerOn = true
        redraw()
        #let email = jq("#inputEmail".toJs).val().to(cstring)
        #let pass = jq("#inputPassword".toJs).val().to(cstring)
        let btn = jq(btnClass.toJs)[0]
        btn.style.display = cstring"none"
        console.log("clicked ")

        when false:
            let stmLogin = sendRequest(
                "POST",
                "/login",
                &"email={email}&pass={pass}",
                [("Content-Type", "application/x-www-form-urlencoded")]
            )
            stmLogin.observe(
                proc (value: Response) =
                    console.log("value:", value.statusCode)
                    currUser.token = $JSON.parse(value.body).token.to(cstring)
                    redraw(),
                    #frm.submit(),
                proc (error: Response) =
                    console.log("error:", error.statusCode)
                    redraw(),
                proc () =
                    #discard
                    console.log("end")
            )

proc loginDialog(): VNode =
    let
        plEmail = "Email"
        plPass = "Пароль"
    console.log("plsHolders:", plEmail, plPass)
    console.log("H.Map:", jsNew H.geo.Point(1, 51))
    result = buildHtml form(class="form-signin", action="", `method` = "post"):
        tdiv(class="text-center mb-4"):
            h1(class="h3 mb-3 font-weight-normal"):
                text "Войти"
        tdiv(class="form-label-group"):
            input(`type`="email", name = "email", id="inputEmail", class="form-control", placeholder = plEmail, required="", autofocus="")
            label(`for`="inputEmail"):
                text plEmail
        tdiv(class="form-label-group"):
            input(`type`="password", name = "pass", id="inputPassword", class="form-control", placeholder = plPass, required="")
            label(`for`="inputPassword"):
                text plPass
        tdiv(class="checkbox mb-3"):
            #label:
                #input(`type`="checkbox", value="remember-me")
                #text " Запомнить меня"
            button(class="btn btn-lg btn-primary btn-block", `type`="submit", onclick = login(".form-signin .btn")):
                text "Войти"
            p(class="mt-5 mb-3 text-muted text-center"):
                text "© 2019"


proc showMap(): VNode =
    result = buildHtml tdiv(class="modal fade", id="mapModal", tabindex="-1", role="dialog", aria-labelledby="mapModalLabel", aria-hidden="true"):
        tdiv(class="modal-dialog map-modal-dialog", role="document"):
            tdiv(class="modal-content"):
                tdiv(class="modal-header"):
                    h6(class="modal-title", id="mapModalLabel"):
                        text "Участок:"
                    button(`type`="button", class="close", data-dismiss="modal", aria-label="Close"):
                        span(aria-hidden="true"):
                            text "x"
                tdiv(class="modal-body map-body"):
                    #text "Здесь будет карта"
                    tdiv(id = "bap-container")


proc clckOpenMap(p: CSectorProcess): proc() = 
    result = proc() =
        currProcess = p
        var elMap = jq("#map-container".toJs)[0]
        elMap.classList.add(cstring"show-map")
        isShowNavMap = true
        var mC = jq(".main-container".toJs)[0]
        mC.classList.add(cstring"map-nav")
        #redraw()
        console.log("clckOpenMap:", elMap)
        spinnerOn = true
        sectStreetGrp.removeAll()
        let stmGetStreet = sendRequest(
            "GET",
            "/sector/streets?" & &"token={currUser.token}&sectorId={p.sector_id}"
        )
        stmGetStreet.observe(
            proc (value: Response) =
                console.log("value:", value.statusCode)
                let sectStrts = JSON.parse(value.body).resp.to(seq[CSectorStreets])
                for strt in sectStrts:
                    let coords = strt.geometry.split(";")
                    for latlng in coords:
                        var lnStr = jsNew H.geo.LineString()
                        console.log("latlng:", latlng)
                        let c = latlng.split(",")
                        for i in countup(0, c.high, 2):
                            console.log("geom:", c[i], c[i+1])
                            lnStr.pushLatLngAlt(c[i].toJs().to(float), c[i+1].toJs().to(float), 1.00)
                        let pOpt = JsObject{
                                style: JsObject{
                                    strokeColor: cstring"rgba(255, 0, 0, 0.2)",
                                    fillColor: cstring"rgba(255, 0, 0, 0.4)",
                                    lineWidth: 10
                                }
                            }
                        let pl = jsNew H.map.Polyline(lnStr, pOpt)
                        sectStreetGrp.addObject pl
                        console.log("lnStr: ", lnStr)
                map.setViewBounds(sectStreetGrp.getBounds(), true)
                redraw(),
            proc (error: Response) =
                console.log("error:", error.statusCode)
                redraw(),
            proc () =
                #discard
                console.log("end")
                spinnerOn = false
                redraw()
        )

proc closeMap() =
    isShowNavMap = false
    var mC = jq(".main-container".toJs)[0]
    var elMap = jq("#map-container".toJs)[0]
    mC.classList.remove(cstring"map-nav")
    elMap.classList.remove(cstring"show-map")
    redraw()

proc showAllProc(): VNode =
    #for p in allSectProc:
        #discard# console.log("p.name:", $(p.name))
    let clsCol = "card-text"#"col-sm-auto themed-grid-col"
    result = buildHtml tdiv(class="card-deck"):
        #showMap()
        for p in allSectProc:
            #discard console.log("p.name:", p)
            tdiv(class="card mb-3 c-sect shadow p-3 bg-white rounded"):
                tdiv(class="card-header"):
                    ul(class="nav nav-pills card-header-pills"):
                        li(class="nav-item"):
                            a(class="nav-link", href="#mapModal", data-toggle="modal", data-target="#mapModal", onclick = clckOpenMap(p)):
                                text "Карта"
                        li(class="nav-item"):
                            a(class="nav-link", href="#take"):
                                text "Взять"
                tdiv(class="card-body"):
                    h6(class="card-title"):
                        text p.name
                    tdiv(class = clsCol):
                        text(#["date_start:" & ]#p.date_start)
                    tdiv(class = clsCol):
                        text(#["date_end:" & ]#p.date_finish)


proc toggleSpinner(): Vnode =
    result = buildHtml tdiv()
    if spinnerOn:
        result = buildHtml tdiv(class="d-flex justify-content-center"):
            tdiv(class="spinner-border text-primary", role="status"):
                span(class="sr-only"):
                    text "Loading..."


proc setEventsModalMap() =
        jq("#mapModal".toJs).on("shown.bs.modal", proc (e: JsObject) =
            let mapBody = jq(".map-body".toJs).get(0)
            let elC = getElemCoords(mapBody)
            console.log(".map-body:: ", elC)
            var elMap = jq("#map-container".toJs)[0]
            elMap.style.top = cstring"0px"#($elC.top & "px")
            elMap.style.left = cstring"0px"#($elC.left & "px")
            mapBody.style.height = cstring($(screen.height.to(float) - 200.00) & "px")
            mapBody.appendChild(elMap)
        )


proc createDom(): VNode =
    result = buildHtml tdiv(class = "main-root"):
        toggleSpinner()
        if currUser.token == "":
            loginDialog()
        elif isShowNavMap:
            nav(class="navbar navbar-expand-lg navbar-light bg-light shadow p-1 mb-0 bg-white rounded overflow-auto"):
                a(class="navbar-brand overflow-auto"):
                    text currProcess.name
                ul(class="navbar-nav mr-auto"):
                    li(class="nav-item"):
                        a(class="badge badge-info", href="#", data-target="#mapclose", onclick = closeMap):
                #button(class="btn btn-outline-success my-2 my-sm-0", `type`="button", onclick = closeMap):
                            text "Закрыть карту"
        else:
            showAllProc()


#proc createMapNav(): VNode =
    #result = buildHtml tdiv(class = "mapnav-root"):
        #text "YES!!!"


setRenderer createDom, "main-control-container"


proc bindMap() =
    let platform = jsNew(H.service.Platform(
                JsObject{
                    app_id: cstring"UHuJLJrJznje69zJ2HB7",
                    app_code: cstring"HdAoJ-BlDvmvb0eksDYqyg",
                    useHTTPS: true
                }
            )
        )
    let pixelRatio = window.devicePixelRatio.to(float)
    let hidpi = pixelRatio > 1.float
    var layerOpts = JsObject{
            tileSize: if hidpi: 512 else: 256,
            pois: true
    }
    if hidpi: layerOpts.ppi = 320

    var mapOpts = JsObject{
        pixelRatio: if hidpi: 2 else: 1,
        noWrap: true
    }
    let defLayers = platform.createDefaultLayers(layerOpts)
    map = jsNew H.Map(
            jq("#map-container".toJs)[0],
            defLayers.normal.map,
            mapOpts
        )
    console.log("platform:: ", platform)
    var behavior = jsNew H.mapevents.Behavior(jsNew H.mapevents.MapEvents(map))
    var ui = H.ui.UI.createDefault(map, defLayers)
    window.addEventListener("resize", () => map.getViewPort().resize())
    map.addObject sectStreetGrp


if currUser.token != "":
    allSectProc = newSeq[CSectorProcess]()
    spinnerOn = true
    redraw()
    let stmLogin = sendRequest(
        "GET",
        "/sector/process?" & &"token={currUser.token}"
    )
    stmLogin.observe(
        proc (value: Response) =
            console.log("value:", value.statusCode)
            allSectProc = JSON.parse(value.body).resp.to(seq[CSectorProcess])
            redraw(),
        proc (error: Response) =
            console.log("error:", error.statusCode)
            redraw(),
        proc () =
            #discard
            console.log("end")
            spinnerOn = false
            redraw()
            bindMap()
            setEventsModalMap()
    )


