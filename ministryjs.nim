# nim -o:public/js/ministry.js js --oldgensym:on --opt:speed -d:release ministryjs.nim
# nim -o:public/js/ministry.js js --debuginfo:on --oldgensym:on ministryjs.nim
# browser-sync start --proxy "http://127.0.0.1:5000" --files "public/js/*.js"

import utiljs
include karax / prelude
import karax / [vstyles]
import jsffi except `&`
import jsbind, async_http_request#, asyncjs
from sugar import `=>`, `->`
from uri import decodeUrl
import src/util/types
import strformat, strutils, times, sequtils
import usersjs

const normalDateFmt = initTimeFormat("yyyy-MM-dd")
var currDate = now().format normalDateFmt
var window {.importjs, nodecl.}: JsObject
var screen {.importjs, nodecl.}: JsObject
var JSON {.importjs, nodecl.}: JsObject
var localStorage {.importjs, nodecl.}: JsObject
var navigator {.importjs, nodecl.}: JsObject


curEngineType = localStorage.getItem("engineType").to(cstring).parseInt()
curEngineType =
    if localStorage.hasOwnProperty("engineType"):
        curEngineType
    else:
        engineTypes.WEBGL.to(int)
localStorage.setItem("engineType", curEngineType)
dwnloadedMaps = jsonParse(localStorage.getItem("dwnloadedMaps").to(cstring)).to(seq[string])
dwnloadedMaps =
    if localStorage.hasOwnProperty("dwnloadedMaps"):
        dwnloadedMaps
    else:
        newSeq[string]()
#dwnloadedMaps.add cstring"bebe"
dbg: console.log("dwnloadedMaps:", dwnloadedMaps)
localStorage.setItem("dwnloadedMaps", jsonStringify dwnloadedMaps)

proc bindMap(engineType: int = curEngineType)


let pIndicator* = newPositionIndicator(20)
let currentPosM = pIndicator.marker

utiljs.pIndicator = pIndicator
let stmAnime = Kefir.interval(20, 1)
stmAnime.observe(
    proc (value: int) =
        #dbg: console.log("stmAnime:", value)
        drawInd()
    #[,
    proc (error: JsObject) =
        console.log("error:", error.statusCode)
    ,
    proc () =
        #discard
        dbg: console.log("stmAnime end:")]#
)

let stmCheckInternet = Kefir.interval(5_000, 1)
stmCheckInternet.observe(
    proc (value: int) =
        let stm = sendRequest(
            "HEAD",
            ""
        )
        stm.observe(
            proc (value: Response) =
                dbg: console.log("value:", value.statusCode, value)
                let old = isInternet
                isInternet = true
                if old != isInternet:
                    redraw()
            ,
            proc (error: Response) =
                #console.log("error:", error.statusCode)
                let old = isInternet
                isInternet = false
                if old != isInternet: redraw()
        )
)




var token = $jq("#token".toJs).val().to(cstring)
var vUser = jq("#user".toJs).val().to(cstring)
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
var currStreets: seq[CSectorStreets]
var currStreetsTmp: seq[CSectorStreets]
var showStreetsEnabled = false
var
    spinnerOn = false
    progressOn = false
    progressProc: int
var scrollToSectId = 0
var onlyMySectors = false
var serchSectByName: string
var setEvtInpSearchSect = false
var currUiSt = JsObject{inpSearch: kstring""}
var map {.exportc.}: JsObject
var ui {.exportc.}: JsObject
var sectStreetGrp = jsNew H.map.Group()
var noMyMsgEl: JsObject
#https://www.w3schools.com/code/tryit.asp?filename=GBBT9UWJK39Y
#[var currentPosM = jsNew H.map.Circle(
    JsObject{lat: 0, lng: 0},
    5,
    JsObject{
        style: JsObject{
            strokeColor: cstring"rgba(0, 0, 0, 1)",
            fillColor: cstring"rgba(255, 0, 0, 1)",
            lineWidth: 1
        }
    }
)]#

proc getAllProccess(myS = false, sectorName = "")
proc hndlUpdOwnSect()
proc closeMap()
proc onMsgClck(): proc()
proc showNoMyMsg() =
    if not onlyMySectors:
        noMyMsgEl.innerHTML = cstring"<span>Внимание: этот участок&nbsp;</span><strong>не твой!</strong>"
    else:
        noMyMsgEl.innerHTML = cstring""


when false:
    var kPrc = proc(emitter: JsObject): proc() =
                result = proc() = discard
                dbg:
                    console.log("emitter:", emitter)
                emitter.emit(1)
    var stm = Kefir.stream(kPrc)
    #stm.log()

proc setTs() =
    timeStamp = $toUnix getTime()


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
                dbg:
                    console.log("resp body:", data.body)
                    console.log("resp:", data.toJs, data.statusCode.toJs, data.status.toJs, result)
    )


proc login(btnClass: kstring): proc() =
    result = proc() =
        spinnerOn = true
        #redraw()
        #let email = jq("#inputEmail".toJs).val().to(cstring)
        #let pass = jq("#inputPassword".toJs).val().to(cstring)
        let btn = jq(btnClass.toJs)[0]
        btn.style.display = cstring"none"
        dbg:
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
                    dbg: console.log("value:", value.statusCode)
                    currUser.token = $jsonParse(value.body).token.to(cstring)
                    redraw(),
                    #frm.submit(),
                proc (error: Response) =
                    console.log("error:", error.statusCode)
                    redraw(),
                proc () =
                    #discard
                    dbg: console.log("end")
            )

proc loginDialog(): VNode =
    let
        plEmail = "Пользователь"
        plPass = "Пароль"
    dbg:
        console.log("plsHolders:", plEmail, plPass)
        console.log("H.Map:", jsNew H.geo.Point(1, 51))
    result = buildHtml form(class="form-signin", action="", `method` = "post"):
        tdiv(class="text-center mb-4"):
            h1(class="h3 mb-3 font-weight-normal"):
                text "Войти"
        tdiv(class="form-label-group"):
            input(`type`="text", name = "email", id="inputEmail", class="form-control", placeholder = plEmail, required="", autofocus="")
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
                text "© 2019-2020"

proc updProcc(): proc() =
    result = proc() =
        spinnerOn = true
        allSectProc = newSeq[CSectorProcess]()
        let p = currProcess
        setTs()
        let stmUpdPrc = sendRequest(# will set finish date<-(now) to give back
            "GET",
            "/sector/process/update?" & &"token={$currUser.token}&processId={p.id}"
        )
        stmUpdPrc.observe(
            proc (value: Response) =
                dbg: console.log("value:", value.statusCode)
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
                dbg: console.log("end")
        )


proc delProcc(): proc() =
    result = proc() =
        spinnerOn = true
        allSectProc = newSeq[CSectorProcess]()
        let p = currProcess
        setTs()
        let stmDelPrc = sendRequest(
            "GET",
            "/sector/process/delete?" & &"token={$currUser.token}&processId={p.id}"
        )
        stmDelPrc.observe(
            proc (value: Response) =
                dbg: console.log("value:", value.statusCode)
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
                dbg: console.log("end")
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
        dbg: console.log("confirmTakeSect: ", currProcess)
        let p = currProcess
        setTs()
        let stmNewPrc = sendRequest(
            "GET",
            "/sector/process/new?" & &"token={$currUser.token}&sectorId={p.sector_id}"
        )
        stmNewPrc.observe(
            proc (value: Response) =
                closeMap() #any case
                dbg: console.log("value:", value.statusCode)
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
                dbg: console.log("end")
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


proc clckOpenMap(p: CSectorProcess): proc() = 
    result = proc() =
        currProcess = p
        var elMap = jq("#map-container".toJs)[0]
        elMap.classList.add(cstring"show-map")
        isShowNavMap = true
        var mC = jq(".main-container".toJs)[0]
        mC.classList.add(cstring"map-nav")
        dbg: console.log("clckOpenMap:", elMap)
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


proc noInternet(): VNode =
    result = buildHtml span:
        discard
    if isInternet:
        return
    result = buildHtml span(class="badge badge-pill badge-danger"): text "Нет интернета"


proc showErrMsg(): VNode =
    result = buildHtml span:
        discard
    if errMsg == "":
        return
    result = buildHtml tdiv(class="alert alert-danger fade show", role="alert", onclick = onMsgClck()):
            text errMsg
            sub: dfn: text " Нажми чтоб убрать"
    

proc showStreetsEnable() =
    showStreetsEnabled = true

proc setStrStatus(iStr: int): proc() =
    result = proc() =
        dbg: console.log("currStreets:", iStr, currStreets, currStreets[iStr].status)
        #if currStreets[iStr].status.toJs().isUndefined:
            #currStreets[iStr].status = StreetStatus.strNotStarted
        let curSt = parseEnum[StreetStatus]($currStreets[iStr].status)
        if curSt == StreetStatus.strFinished: 
            currStreets[iStr].status = $StreetStatus.strNotStarted
        else:
            dbg: console.log("currStreets:", currStreets[iStr].status)
            currStreets[iStr].status = $succ(curSt)
            dbg: console.log("currStreets:", currStreets[iStr].status)
        dbg: console.log("ord status: ", ord(parseEnum[StreetStatus]($currStreets[iStr].status)))

proc setStrTotFam(iStr: int): proc(ev: Event; n: VNode) =
    result = proc(ev: Event; n: VNode) =
        currStreetsTmp[iStr].totalFamilies = if n.text == "": 0 else: n.text.parseInt
        dbg: console.log("currStreets:", iStr, n.text.parseInt, currStreets[iStr].totalFamilies)


proc saveStreets(): proc() =
    result = proc() =
        showStreetsEnabled = false
        var streets: seq[string]
        let polyStrts = sectStreetGrp.getObjects()
        for i,str in currStreets:
            let id = str.id
            let nSt = ord(parseEnum[StreetStatus]($str.status))
            currStreets[i].totalFamilies = currStreetsTmp[i].totalFamilies
            streets.add [$str.id, $str.sector_id, $nSt, $currStreets[i].totalFamilies].join(",")
            for p in polyStrts:
                let pStrtId = p.getData().to(int)
                if id == pStrtId:
                    setPolyStyleByStat(p, str.status)
        let setStr = streets.join(";")
        dbg: console.log("setStr:", setStr)
        setTs()
        let stmUpd = sendRequest(
            "GET",
            "/streets/status/update?" & &"token={$currUser.token}&streets={setStr}"
        )
        stmUpd.observe(
            proc (value: Response) =
                dbg: console.log("value:", value.statusCode)
            ,
            proc (error: Response) =
                console.log("error:", error.statusCode)
            ,
            proc () =
                redraw()
                dbg: console.log("end")
        )
        #errMsg = "Сохранение статуса улиц пока не работает..."

proc showStreets(): VNode =
    var strSt = (color: "danger", stDescr: " - не пройдена")
    result = buildHtml tdiv:
        tdiv(class="d-flex justify-content-center mt-6"):
            tdiv(class="overflow-auto px-3 vh-75 w-75 bg-light shadow-lg border rounded-lg"):
                for i,str in currStreets.pairs:
                    let tf = str.totalFamilies
                    let sSt = parseEnum[StreetStatus]($str.status)
                    if sSt == StreetStatus.strStarted:
                        strSt = (color: "primary", stDescr: " - не закончена")
                    elif sSt == StreetStatus.strFinished:
                        strSt = (color: "success", stDescr: " - пройдена")
                    else:
                        strSt = (color: "danger", stDescr: " - не начата")
                    tdiv(class="py-2 row"):
                        button(`type`="button", class="col text-nowrap overflow-auto ml-2 mr-2 btn btn-outline-" &
                                    strSt.color & " btn-sm", onclick = setStrStatus(i)):
                            text str.name
                            #discard dbg: console.log("street:->", str)
                        input(`type`="number", #[inputmode="numeric",]# class="col-2 mr-2 px-1", id="strfam" & $i & $tf, value = $tf, oninput = setStrTotFam(i))
                    tdiv(class="overflow-auto text-nowrap border-bottom pb-2 mt-n3"):
                        text strSt.stDescr
            tdiv:
                button(`type`="button", class="btn btn-success btn", onclick = saveStreets()):
                    text "ok"
    
proc clckProccSect(p: CSectorProcess): proc() = 
    result = proc() =
        dbg: console.log("clckProccSect: ", p)
        currProcess = p

proc hndlUpdOwnSect() =
    dbg: console.log("start upd...")
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
    showNoMyMsg()
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
        showErrMsg()
        nav(class="navbar fixed-top navbar-expand navbar-light bg-light shadow p-1 mb-0 bg-white rounded overflow-auto"):
            button(class="navbar-toggler", `type`="button", data-toggle="collapse",
                    data-target="#navbarTogglerSectors", aria-controls="navbarTogglerSectors", aria-expanded="false", aria-label="Toggle navigation"):
                span(class="navbar-toggler-icon")
            #a(class="navbar-brand mw-75 overflow-auto"):
                #text currProcess.name
            tdiv(class="collapse navbar-collapse", id="navbarTogglerSectors"):
                tdiv(class="custom-control custom-switch py-3"):
                    input(`type`="checkbox", class="custom-control-input", id="ownSectors")
                    label(class="custom-control-label", `for`="ownSectors"):
                        text "Мои"
                input(`type`="text", class="form-control mw-50", id="searchSector",
                            aria-describedby="searchHelp", placeholder="искать...",
                            value = currUiSt.inpSearch.to(kstring)
                    )
                discard dbg: console.log("currUser:", currUser)
                if currUser.role == "superadmin":
                    ul(class="navbar-nav mr-auto"):
                        li(class="nav-item"):
                            a(class="nav-link", onclick = editUsers()):
                                text "Возвещатели"
                ul(class="navbar-nav mr-auto"):
                    li(class="nav-item"):
                        a(class="nav-link", onclick = logout):
                            text "Выйти"
            noInternet()
        if isShowUsers:
            showUsers()
        else:
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
                            [p.firstname, p.lastname].join(" ")
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
                                    discard dbg:
                                        console.log("currDate > $p.date_finish", currDate, p.date_finish)
                        tdiv(class="card-body"):
                            h6(class="card-title"):
                                text p.name
                            tdiv(class = clsCol):
                                text(stDate)
                            tdiv(class = clsCol):
                                text(finDate)
                            tdiv(class = clsCol & " d-flex justify-content-end"):
                                h5:
                                    span(class = "badge badge-primary"):
                                        text kstring($p.totalFamilies)
        



proc toggleSpinner(): Vnode =
    result = buildHtml tdiv()
    if spinnerOn:
        result = buildHtml tdiv(class="d-flex justify-content-center mt-6"):
            tdiv(class="spinner-border text-primary", role="status"):
                span(class="sr-only"):
                    text "Загрузка..."

proc toggleProgress(): Vnode =
    result = buildHtml tdiv()
    let cText = if progressProc < 5: "text-dark" else: ""
    if progressOn:
        result = buildHtml tdiv(class="progress mt-6"):
            tdiv(class="progress-bar progress-bar-striped progress-bar-animated " & cText, role="progressbar", style = style((StyleAttr.width, cstring($progressProc & "%")))#[, `style`=cstring("width: " & $progressProc & "%;")]#,
                aria-valuenow = $progressProc, aria-valuemin="0", aria-valuemax="100"):
                text $progressProc & "%"



proc mapDownload() =
    let max = map.getBaseLayer().getProvider().max.to(int)
    map.storeContent(proc(r: JsObject) =
        let
            prgsT = r.getTotal().to(int)
            prgsP = r.getProcessed().to(int)
        progressOn = prgsT > prgsP
        if not progressOn:
            dbg: console.log("currProcess:", currProcess)
            dwnloadedMaps.add $currProcess.sector_internal_id
            localStorage.setItem("dwnloadedMaps", jsonStringify dwnloadedMaps)
        progressProc = int(prgsP * 100 / prgsT)
        redraw(),
        #dbg: console.log("dwnld progress:", r.getTotal(), " ", r.getProcessed(), " ", r.getState(), " ", max),
        sectStreetGrp.getBoundingBox(),
        max - 4,
        max
    )



proc setEventsModalMap() =
    jq("#mapModal".toJs).on("shown.bs.modal", proc (e: JsObject) =
        let mapBody = jq(".map-body".toJs).get(0)
        let elC = getElemCoords(mapBody)
        dbg: console.log(".map-body:: ", elC)
        var elMap = jq("#map-container".toJs)[0]
        elMap.style.top = cstring"0px"#($elC.top & "px")
        elMap.style.left = cstring"0px"#($elC.left & "px")
        mapBody.style.height = cstring($(screen.height.to(float) - 200.00) & "px")
        mapBody.appendChild(elMap)
    )


proc createDom(): VNode =
    result = buildHtml tdiv(class = "main-root"):
        toggleSpinner()
        toggleProgress()
        showConfirm "takeModal", takeSectModalBody()
        showConfirm "gBackModal", giveBackModalBody()
        showConfirm "isProccessedModal", proccessedModalBody()
        if currUser.token == "":
            loginDialog()
        elif isShowNavMap:
            nav(class="navbar fixed-top navbar-expand navbar-light bg-light shadow p-1 mb-0 bg-white rounded overflow-auto"):
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
                        if onlyMySectors and not showStreetsEnabled:
                            li(class="nav-item"):
                                a(id="show-streets", class="nav-link", onclick = showStreetsEnable):
                                    text "Улицы"
                            if dwnloadedMaps.count($currProcess.sector_internal_id) == 0:
                                li(class="nav-item"):
                                    a(id="map-download", class="nav-link", onclick = mapDownload):
                                        text "Скачать"
                        if not showStreetsEnabled:
                            li(class="nav-item"):
                                a(id="cl-map", class="nav-link", onclick = closeMap):
                                    text "Закр.карту"
                noInternet()
                showErrMsg()
            if showStreetsEnabled:
                showStreets()
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

proc bindGps() =
    #let stmGps = Kefir.fromEvents(chgEl, "input", getValues).toProperty(getValues)
    proc getPos(position: JsObject) =
        if map == nil:
            return
        let newGeoPos = JsObject{
            lat: position.coords.latitude,
            lng: position.coords.longitude
        }
        if curEngineType == engineTypes.P2D.to(int) and #if P2D then change marker pos if > 10 meter diff 
                    currentPosM.getGeometry().distance(newGeoPos).to(float) > 10.00 and
                    not isInternet: #and only if no internet
            currentPosM.setGeometry(newGeoPos)
        elif curEngineType == engineTypes.P2D.to(int) and isInternet:
            currentPosM.setGeometry(newGeoPos)
        if curEngineType == engineTypes.WEBGL.to(int):
            currentPosM.setGeometry(newGeoPos)
        dbg: console.log("position: ", map, position, currentPosM.getGeometry(), map.geoToScreen(currentPosM.getGeometry()))
    proc errorHandler(errorObj: JsObject) = 
        console.log cstring($errorObj.code.to(int) & ": " & errorObj.message.to(cstring))
    navigator.geolocation.watchPosition(getPos, errorHandler)
bindGps()

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
    #stmUiChg.log()
    proc wrpS(vS: JsObject): JsObject =
        spinnerOn = true
        allSectProc = newSeq[CSectorProcess]()
        redraw()
        result = getAllProccess2(vS.isOwnSect.to(bool), $vS.inpSearch.to(cstring))
    let stmResult = stmUiChg.flatMapLatest(wrpS)
    stmResult.observe(
        proc (value: Response) =
            dbg: console.log("value:", value.statusCode, value)
            allSectProc = parseResp(value.body, CStatusResp[seq[CSectorProcess]]).resp
            spinnerOn = false
            redraw()
        ,
        proc (error: Response) =
            console.log("error:", error.statusCode)
        ,
        proc () =
            dbg: console.log("end")
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
        dbg: console.log("getStreets(isStart:", interrupt)
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
            dbg: console.log("value:", value.statusCode)
            let respSect = parseResp(value.body, CStatusResp[seq[CSectorStreets]])
            let sectStrts = respSect.resp
            currStreets = sectStrts
            currStreetsTmp = sectStrts
            #dbg: console.log("resp status:", cstring($respSect.status), cstring"loggedOut")
            if sectStrts.len == 0:
                return
            for strt in sectStrts:
                dbg: console.log("street:", strt.name)
                let stStat = ord parseEnum[StreetStatus]($strt.status)
                let coords = strt.geometry.split(";")
                for latlng in coords:
                    var lnStr = jsNew H.geo.LineString()
                    #dbg: console.log("latlng:", latlng)
                    let c = latlng.split(",")
                    for i in countup(0, c.high, 2):
                        #dbg: console.log("geom:", c[i], c[i+1])
                        lnStr.pushLatLngAlt(c[i].toJs().to(float), c[i+1].toJs().to(float), 1.00)
                    let pOpt = JsObject{
                            data: strt.id
                        }
                    let pl = jsNew H.map.Polyline(lnStr, pOpt)
                    setPolyStyleByStat(pl, strt.status)
                    sectStreetGrp.addObject pl
                    dbg: console.log("pOpt:", pl.getData())
            #map.setViewBounds(sectStreetGrp.getBounds(), true)
            map.getViewModel().setLookAtData(JsObject{
                bounds: sectStreetGrp.getBoundingBox()
            });
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
    dbg: console.log("yes bindEvtsMapScreen")



setRenderer createDom, "main-control-container", proc() =
            dbg: console.log("post render!!!")
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
            


proc bindMap(engineType: int = curEngineType) =
    let platform = jsNew(H.service.Platform(
                JsObject{
                    apikey: currUser.apiKey,
                    useHTTPS: true
                }
            )
        )
    let pixelRatio = if window.devicePixelRatio.isUndefined: 1.float else: window.devicePixelRatio.to(float)
    let hidpi = pixelRatio > 1.float
    var layerOpts = JsObject{
            tileSize: 512, #if hidpi: 512 else: 256,
            pois: true
    }
    if hidpi: layerOpts.ppi = 320
    var mapOpts = JsObject{
        engineType: engineType,
        #pixelRatio: if hidpi: 2 else: 1,
        pixelRatio: pixelRatio,
        noWrap: true
    }
    let defLayers = platform.createDefaultLayers(layerOpts)
    let mapContainer = jq("#map-container".toJs)[0]
    mapContainer.innerHTML = ""
    map = jsNew H.Map(
            mapContainer,
            defLayers.raster.normal.map,
            mapOpts
        )
    #map.setBaseLayer(custBaseLayer)
    map.getBaseLayer().setMax(20)
    dbg: console.log("platform:: ", platform)
    var behavior = jsNew H.mapevents.Behavior(jsNew H.mapevents.MapEvents(map))
    ui = H.ui.UI.createDefault(map, defLayers)
    ui.removeControl("zoom")
    var
        cntrRMap = jsNew H.ui.Control()
        cntrNoMy = jsNew H.ui.Control()
    cntrRMap.setAlignment(H.ui.LayoutAlignment.RIGHT_BOTTOM)
    cntrNoMy.setAlignment(H.ui.LayoutAlignment.TOP_CENTER)
    var
        cntrRMapBtn = (jsNew H.ui.base.PushButton(JsObject{label: cstring"<h6>Растр</h6>"}))
            .addClass(cstring"d-flex align-items-center justify-content-center")
        noMyMsg = jsNew H.ui.base.Element(cstring"h5", cstring"d-flex align-items-center justify-content-center pt-4 text-danger")
    cntrRMap.addChild cntrRMapBtn
    cntrNoMy.addChild noMyMsg
    ui.addControl("rastr", cntrRMap)
    ui.addControl("noMyMsg", cntrNoMy)
    noMyMsgEl = noMyMsg.getElement()
    showNoMyMsg()
    dbg: console.log("noMyMsg:", noMyMsg.getElement())
    cntrRMapBtn.setState(
        if curEngineType == engineTypes.WEBGL.to(int): H.ui.base.Button.State.UP
        else: H.ui.base.Button.State.DOWN
    )
    cntrRMapBtn.addEventListener("statechange", proc(evt: JsObject) =
            if evt.target.getState() == H.ui.base.Button.State.UP:
                curEngineType = engineTypes.WEBGL.to(int)
            else:
                curEngineType = engineTypes.P2D.to(int)
            localStorage.setItem("engineType", curEngineType)
            dbg: console.log("statechange:", evt.target.getState())
            bindMap()
    )
    window.addEventListener("resize", () => map.getViewPort().resize())
    map.addObject currentPosM
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
            dbg: console.log("value:", value.statusCode, value)
            allSectProc = parseResp(value.body, CStatusResp[seq[CSectorProcess]]).resp
        ,
            #redraw(),
        proc (error: Response) =
            console.log("error:", error.statusCode)
        ,
            #redraw(),
        proc () =
            #discard
            dbg: console.log("end")
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



