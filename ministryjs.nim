# nim -o:public/js/ministry.js js --oldgensym:on --opt:speed -d:release ministryjs.nim
# nim -o:public/js/ministry.js js --debuginfo:on --oldgensym:on ministryjs.nim
# browser-sync start --proxy "http://127.0.0.1:5000" --files "public/js/*.js"

include karax / prelude
import jsffi except `&`
import jsbind, async_http_request#, asyncjs
from sugar import `=>`, `->`
from uri import decodeUrl
import src/util/types
import strformat, strutils, times
import utiljs

const normalDateFmt = initTimeFormat("yyyy-MM-dd")
var currDate = now().format normalDateFmt
var console {.importjs, nodecl.}: JsObject
var window {.importjs, nodecl.}: JsObject
var document {.importjs, nodecl.}: JsObject
var screen {.importjs, nodecl.}: JsObject
proc jq(selector: JsObject): JsObject {.importjs: "$$(#)".}
proc jqData(obj: JsObject, hndlrs: cstring): JsObject {.importjs: "$$._data(#,#)".}
var JSON {.importjs, nodecl.}: JsObject
var localStorage {.importjs, nodecl.}: JsObject
proc jsonParse(s: cstring): JsObject {.importjs: "JSON.parse(#)".}
var Kefir {.importjs, nodecl.}: JsObject
var H {.importjs, nodecl.}: JsObject

var token = $jq("#token".toJs).val().to(cstring)
var vUser = jq("#user".toJs).val().to(cstring)
var currUser = CUser()
if vUser == "":
    try:
        vUser = localStorage.getItem("user").to(cstring)
        currUser = jsonParse(decodeUrl $vUser).resp.to(CUser)
    except:
        discard
    #if currUser.token != token:
        #currUser = CUser(token: token)
        #localStorage.setItem("user", "")
else:
    localStorage.setItem("user", vUser)
    currUser = jsonParse(decodeUrl $vUser).resp.to(CUser)
currUser.token = token
var currProcess: CSectorProcess
var allSectProc: seq[CSectorProcess]
var spinnerOn = false
var isShowNavMap = false
var scrollToSectId = 0
var onlyMySectors = false
var errMsg: string
var serchSectByName: string
var setEvtInpSearchSect = false
var currUiSt = JsObject{inpSearch: kstring""}
var map: JsObject
var sectStreetGrp = jsNew H.map.Group()

proc getAllProccess(myS = false, sectorName = "")
proc hndlUpdOwnSect()
proc parseResp(bdy: string, T: typedesc): T
proc closeMap()

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
                        StatusResp[TokenResp](status: true, resp: jsonParse(data.body).to(TokenResp))
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
                    currUser.token = $jsonParse(value.body).token.to(cstring)
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

proc updProcc(): proc() =
    result = proc() =
        spinnerOn = true
        allSectProc = newSeq[CSectorProcess]()
        let p = currProcess
        let stmUpdPrc = sendRequest(# will set finish date<-(now) to give back
            "GET",
            "/sector/process/update?" & &"token={$currUser.token}&processId={p.id}"
        )
        stmUpdPrc.observe(
            proc (value: Response) =
                console.log("value:", value.statusCode)
                let respSect = parseResp(value.body, CStatusResp[seq[CSectorProcess]])
                if respSect.status == "unknown":
                    #discard
                    errMsg = $respSect.message
                let ownSEl = document.getElementById("ownSectors")
                if ownSEl != nil:
                    ownSEl.checked = true
                onlyMySectors = true
                hndlUpdOwnSect()
            ,
            proc (error: Response) =
                console.log("error:", error.statusCode)
            ,
            proc () =
                redraw()
                console.log("end")
        )


proc delProcc(): proc() =
    result = proc() =
        spinnerOn = true
        allSectProc = newSeq[CSectorProcess]()
        let p = currProcess
        let stmDelPrc = sendRequest(
            "GET",
            "/sector/process/delete?" & &"token={$currUser.token}&processId={p.id}"
        )
        stmDelPrc.observe(
            proc (value: Response) =
                console.log("value:", value.statusCode)
                let respSect = parseResp(value.body, CStatusResp[int])
                if respSect.status == "unknown":
                    #discard
                    errMsg = $respSect.message
                let ownSEl = document.getElementById("ownSectors")
                if ownSEl != nil:
                    ownSEl.checked = true
                onlyMySectors = true
                hndlUpdOwnSect()
            ,
            proc (error: Response) =
                console.log("error:", error.statusCode)
            ,
            proc () =
                redraw()
                console.log("end")
        )


proc chgUiState(chgEl: JsObject): JsObject =
    proc getValues(): JsObject =
        onlyMySectors = document.getElementById("ownSectors").checked.to(bool)
        currUiSt = JsObject{inpSearch: document.getElementById("searchSector").value.to(cstring),
                    isOwnSect: onlyMySectors}
        return currUiSt
    result = Kefir.fromEvents(chgEl, "input", getValues).toProperty(getValues)


proc confirmTakeSect(): proc() = 
    result = proc() =
        spinnerOn = true
        allSectProc = newSeq[CSectorProcess]()
        console.log("confirmTakeSect: ", currProcess)
        let p = currProcess
        let stmNewPrc = sendRequest(
            "GET",
            "/sector/process/new?" & &"token={$currUser.token}&sectorId={p.sector_id}"
        )
        stmNewPrc.observe(
            proc (value: Response) =
                closeMap() #any case
                console.log("value:", value.statusCode)
                let respSect = parseResp(value.body, CStatusResp[seq[CSectorProcess]])
                if respSect.status == "unknown":
                    #discard
                    errMsg = $respSect.message
                let ownSEl = document.getElementById("ownSectors")
                if ownSEl != nil:
                    ownSEl.checked = true
                onlyMySectors = true
                hndlUpdOwnSect()
            ,
            proc (error: Response) =
                console.log("error:", error.statusCode)
            ,
            proc () =
                redraw()
                console.log("end")
        )
    

proc takeSectModalBody(): VNode =
    result = buildHtml tdiv(class="modal-body"):
        tdiv:
            text "Взять участок на обработку?"
        tdiv(class="mx-auto"):
            button(`type`="button", class="btn btn-success float-left", data-dismiss="modal", onclick = confirmTakeSect()):
                text "Да"
            button(`type`="button", class="btn btn-danger float-right", data-dismiss="modal"):
                text "Нет"

proc giveBackModalBody(): VNode =
    result = buildHtml tdiv(class="modal-body"):
        tdiv:
            text "Уверен, что хочешь сдать участок?"
        tdiv(class="mx-auto"):
            button(`type`="button", class="btn btn-success float-left", data-dismiss="modal", data-toggle="modal", data-target="#isProccessedModal"):
                text "Да"
            button(`type`="button", class="btn btn-danger float-right", data-dismiss="modal"):
                text "Нет"

proc proccessedModalBody(): VNode =
    result = buildHtml tdiv(class="modal-body"):
        tdiv:
            text "Был участок обработан?"
        tdiv(class="mx-auto"):
            tdiv(class="clearfix"):
                button(`type`="button", class="btn btn-success float-left", data-dismiss="modal", onclick=updProcc()):
                    text "Сдать, как обработанный"
                button(`type`="button", class="btn btn-danger float-right", data-dismiss="modal", onclick=delProcc()):
                    text "Сдать, как не обработанный"
            tdiv(class="clearfix"):
                text "или"
            button(`type`="button", class="btn btn-secondary", data-dismiss="modal"):
                text "Не сдавать"
    


proc showConfirm(modalId: string, bdy: VNode): VNode =
    let lblM = modalId & "Label"
    result = buildHtml tdiv(class="modal fade", id=modalId, tabindex="-1", role="dialog", aria-labelledby=lblM, aria-hidden="true"):
        tdiv(class="modal-dialog", role="document"):
            tdiv(class="modal-content"):
                tdiv(class="modal-header"):
                    h6(class="modal-title", id=lblM):
                        text currProcess.name
                    button(`type`="button", class="close", data-dismiss="modal", aria-label="Close"):
                        span(aria-hidden="true"):
                            text "x"
                bdy

proc parseResp(bdy: string, T: typedesc): T =
    result = cast[T](jsonParse(bdy))
    if $result.status == "loggedOut":
        currUser.token = ""
        isShowNavMap = false
        var elMap = jq("#map-container".toJs)[0]
        elMap.classList.remove(cstring"show-map")
        redraw()


proc clckOpenMap(p: CSectorProcess): proc() = 
    result = proc() =
        currProcess = p
        var elMap = jq("#map-container".toJs)[0]
        elMap.classList.add(cstring"show-map")
        isShowNavMap = true
        var mC = jq(".main-container".toJs)[0]
        mC.classList.add(cstring"map-nav")
        console.log("clckOpenMap:", elMap)
        spinnerOn = true
        scrollToSectId = p.sector_id
        sectStreetGrp.removeAll()

proc closeMap() =
    isShowNavMap = false
    var mC = jq(".main-container".toJs)[0]
    var elMap = jq("#map-container".toJs)[0]
    mC.classList.remove(cstring"map-nav")
    elMap.classList.remove(cstring"show-map")
    spinnerOn = false

proc clckProccSect(p: CSectorProcess): proc() = 
    result = proc() =
        console.log("clckProccSect: ", p)
        currProcess = p

proc hndlUpdOwnSect() =
    console.log("start upd...")
    var ownS = jq("#ownSectors".toJs)[0]
    if ownS != nil:
        onlyMySectors = ownS.checked.to(bool)
    getAllProccess onlyMySectors



    
proc onMsgClck(): proc() = 
    result = proc() =
        errMsg = ""


proc updOwnSect(): proc() = 
    result = hndlUpdOwnSect

proc logout() =
    currUser.token = ""
    document.cookie = cstring"token=none;path=/"
    document.location.replace("/")

proc allowTake(p: CSectorProcess): bool =
    result = false
    if p.date_start == "":
        return true
    if p.date_finish == "":
        return false
    if ((now() - 1.weeks).format normalDateFmt) > $p.date_finish:
        return true

proc showAllProc(): VNode =
    #for p in allSectProc:
        #discard# console.log("p.name:", $(p.name))
    let clsCol = "card-text"#"col-sm-auto themed-grid-col"
    result = buildHtml tdiv:
        if errMsg != "":
            tdiv(class="alert alert-danger fade show", role="alert", onclick = onMsgClck()):
                text errMsg
        nav(class="navbar fixed-top navbar-expand-sm navbar-light bg-light shadow p-1 mb-0 bg-white rounded overflow-auto"):
            button(class="navbar-toggler", `type`="button", data-toggle="collapse",
                    data-target="#navbarTogglerSectors", aria-controls="navbarTogglerSectors", aria-expanded="false", aria-label="Toggle navigation"):
                span(class="navbar-toggler-icon")
            #a(class="navbar-brand mw-75 overflow-auto"):
                #text currProcess.name
            tdiv(class="collapse navbar-collapse", id="navbarTogglerSectors"):
                tdiv(class="custom-control custom-switch"):
                    input(`type`="checkbox", class="custom-control-input", id="ownSectors")
                    label(class="custom-control-label", `for`="ownSectors"):
                        text "Мои"
                input(`type`="text", class="form-control mw-50", id="searchSector",
                            aria-describedby="searchHelp", placeholder="искать...",
                            value = currUiSt.inpSearch.to(kstring)
                    )
                ul(class="navbar-nav mr-auto"):
                    li(class="nav-item"):
                        a(class="nav-link", onclick = logout):
                            text "Выйти"
        tdiv(class="card-deck"):
            for p in allSectProc:
                #discard console.log("p.name:", p)
                let stDate =
                    if p.date_start != "":
                        "Взят: " & p.startDate.format( initTimeFormat("dd'.'MM'.'yyyy") )
                    else:
                        ""
                let finDate =
                    if p.date_finish != "":
                        "Сдан: " & p.finishDate.format( initTimeFormat("dd'.'MM'.'yyyy") )
                    else:
                        ""
                let sectId = kstring($p.sector_id)
                tdiv(id=sectId, class="card mb-3 c-sect shadow p-3 bg-white rounded"):
                    tdiv(class="card-header"):
                        ul(class="nav nav-pills card-header-pills"):
                            li(class="nav-item"):
                                a(class="nav-link", href="#mapModal", data-toggle="modal", data-target="#mapModal", onclick = clckOpenMap(p)):
                                    text "Карта"
                            if allowTake(p):
                                li(class="nav-item"):
                                    a(class="nav-link", href="#takeModal", data-toggle="modal", data-target="#takeModal", onclick = clckProccSect(p)):
                                        text "Взять"
                            elif p.userId == currUser.id and onlyMySectors:
                                li(class="nav-item"):
                                    a(class="nav-link", href="#gBackModal", data-toggle="modal", data-target="#gBackModal", onclick = clckProccSect(p)):
                                        text "Сдать"
                                discard console.log("currDate > $p.date_finish", currDate, p.date_finish)
                    tdiv(class="card-body"):
                        h6(class="card-title"):
                            text p.name
                        tdiv(class = clsCol):
                            text(#["date_start:" & ]#stDate)
                        tdiv(class = clsCol):
                            text(#["date_end:" & ]#finDate)
        



proc toggleSpinner(): Vnode =
    result = buildHtml tdiv()
    if spinnerOn:
        result = buildHtml tdiv(class="d-flex justify-content-center"):
            tdiv(class="spinner-border text-primary", role="status"):
                span(class="sr-only"):
                    text "Загрузка..."


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
        showConfirm "takeModal", takeSectModalBody()
        showConfirm "gBackModal", giveBackModalBody()
        showConfirm "isProccessedModal", proccessedModalBody()
        if currUser.token == "":
            loginDialog()
        elif isShowNavMap:
            nav(class="navbar navbar-expand-sm navbar-light bg-light shadow p-1 mb-0 bg-white rounded overflow-auto"):
                button(class="navbar-toggler", `type`="button", data-toggle="collapse",
                        data-target="#navbarTogglerMap", aria-controls="navbarTogglerMap", aria-expanded="false", aria-label="Toggle navigation"):
                    span(class="navbar-toggler-icon")
                a(class="navbar-brand mw-75 overflow-auto"):
                    text currProcess.name
                tdiv(class="collapse navbar-collapse", id="navbarTogglerMap"):
                    ul(class="navbar-nav mr-auto"):
                        if allowTake(currProcess):
                            li(class="nav-item"):
                                a(class="nav-link", href="#takeModal", data-toggle="modal", data-target="#takeModal"):
                                    text "Взять"
                        li(class="nav-item"):
                            a(id="cl-map", class="nav-link", onclick = closeMap):
                                text "Закр.карту"
        else:
            showAllProc()


proc getAllProccess2(myS = false, sectorName = ""): JsObject =
    let rUid =
        if not myS: ""
        else: &"&userId={currUser.id}"
    let sName =
        if sectorName != "":
            &"&sectorName={sectorName}"
        else: ""
    result = sendRequest(
        "GET",
        "/sector/process?" & &"token={currUser.token}" & rUid & sName
    )

proc bindSearchSector() =
    let searchEl = document.getElementById("searchSector")
    let isOwnSectEl = document.getElementById("ownSectors")
    if searchEl == nil:
        setEvtInpSearchSect = false
        return
    if setEvtInpSearchSect:
        return# input event already set
    setEvtInpSearchSect = true
    let stmSearchEl = chgUiState(searchEl)
    let stmOwnSect = chgUiState(isOwnSectEl)
    #stmOwnSect.log()
    var stmUiChg = Kefir.merge(toJs [stmSearchEl, stmOwnSect])
    stmUiChg.log()
    proc wrpS(vS: JsObject): JsObject =
        spinnerOn = true
        allSectProc = newSeq[CSectorProcess]()
        redraw()
        result = getAllProccess2(vS.isOwnSect.to(bool), $vS.inpSearch.to(cstring))
    let stmResult = stmUiChg.flatMapLatest(wrpS)
    stmResult.observe(
        proc (value: Response) =
            console.log("value:", value.statusCode, value)
            allSectProc = parseResp(value.body, CStatusResp[seq[CSectorProcess]]).resp
            spinnerOn = false
            redraw()
        ,
        proc (error: Response) =
            console.log("error:", error.statusCode)
        ,
        proc () =
            console.log("end")
    )

var stmClMap: JsObject
proc bindEvtsMapScreen() =
    let clMapEl = document.getElementById("cl-map")
    if clMapEl == nil:
        stmClMap = nil
        return
    if stmClMap != nil:
        return
    proc getStreets(interrupt: bool): JsObject =
        console.log("getStreets(isStart:", interrupt)
        if interrupt:
            return Kefir.never()
        result = sendRequest(
            "GET",
            "/sector/streets?" & &"token={currUser.token}&sectorId={currProcess.sector_id}"
        )
    let stmOpenMapScr = Kefir.constant(false)
    stmClMap = Kefir.fromEvents(clMapEl, "click").map(() => true)
    let stmGetStreet = Kefir.merge(toJs [stmOpenMapScr, stmClMap]).flatMapLatest(getStreets)
    stmGetStreet.observe(
        proc (value: Response) =
            console.log("value:", value.statusCode)
            let respSect = parseResp(value.body, CStatusResp[seq[CSectorStreets]])
            let sectStrts = respSect.resp
            #console.log("resp status:", cstring($respSect.status), cstring"loggedOut")
            if sectStrts.len == 0:
                return
            for strt in sectStrts:
                let coords = strt.geometry.split(";")
                for latlng in coords:
                    var lnStr = jsNew H.geo.LineString()
                    #console.log("latlng:", latlng)
                    let c = latlng.split(",")
                    for i in countup(0, c.high, 2):
                        #console.log("geom:", c[i], c[i+1])
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
                    #console.log("lnStr: ", lnStr)
            map.setViewBounds(sectStreetGrp.getBounds(), true)
            spinnerOn = false
            redraw(),
        proc (error: Response) =
            console.log("error:", error.statusCode)
            redraw(),
        proc () =
            discard
            #[console.log("end streets")
            spinnerOn = false
            redraw()]#
    )
    console.log("yes bindEvtsMapScreen")



setRenderer createDom, "main-control-container", proc() =
            console.log("post render!!!")
            currDate = now().format normalDateFmt
            if document.getElementById("ownSectors") != nil:
                document.getElementById("ownSectors").checked = onlyMySectors    
            bindSearchSector()
            bindEvtsMapScreen()
            if scrollToSectId != 0:
                let sIdEl = toJs(["#", $scrollToSectId, ".card"].join("")).jq()
                if sIdEl.length.to(int) == 0:
                    return
                scrollToSectId = 0
                sIdEl[0].scrollIntoView(JsObject{behavior: cstring"auto", `block`: cstring"start", inline: cstring"nearest"})
                when false:
                    jq("html, body".toJs).animate(JsObject{
                                scrollTop: jq(sIdEl).offset().top
                            }, 2000)
            


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




proc getAllProccess(myS = false, sectorName = "") =
    spinnerOn = true
    allSectProc = newSeq[CSectorProcess]()
    redraw()
    let rUid =
        if not myS: ""
        else: &"&userId={currUser.id}"
    let sName =
        if sectorName != "":
            &"&sectorName={sectorName}"
        else: ""
    let stmLogin = sendRequest(
        "GET",
        "/sector/process?" & &"token={currUser.token}" & rUid & sName
    )
    stmLogin.observe(
        proc (value: Response) =
            console.log("value:", value.statusCode, value)
            allSectProc = parseResp(value.body, CStatusResp[seq[CSectorProcess]]).resp
        ,
            #redraw(),
        proc (error: Response) =
            console.log("error:", error.statusCode)
        ,
            #redraw(),
        proc () =
            #discard
            console.log("end")
            spinnerOn = false
            redraw()
    )


if currUser.token != "":
    allSectProc = newSeq[CSectorProcess]()
    spinnerOn = true
    redraw()
    bindMap()
    setEventsModalMap()
    getAllProccess()



