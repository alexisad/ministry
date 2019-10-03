# nim -o:public/js/ministry.js js --oldgensym:on --opt:speed -d:release ministryjs.nim
# nim -o:public/js/ministry.js js --debuginfo:on --oldgensym:on ministryjs.nim
# browser-sync start --proxy "http://127.0.0.1:5000" --files "public/js/*.js"

include karax / prelude
import jsffi, jsbind, async_http_request, asyncjs
from sugar import `=>`, `->`
import src/util/types
import strformat


var console {.importjs, nodecl.}: JsObject
# import the "$" function
proc jq(selector: JsObject): JsObject {.importjs: "$$(#)".}
var JSON {.importjs, nodecl.}: JsObject
var Kefir {.importjs, nodecl.}: JsObject
var H {.importjs, nodecl.}: JsObject
var token = $jq("#token".toJs).val().to(cstring)
var currUser = User(token: token)

when false:
    var kPrc = proc(emitter: JsObject): proc() =
                result = proc() = discard
                console.log("emitter:", emitter)
                emitter.emit(1)
    var stm = Kefir.stream(kPrc)
    stm.log()

proc sendRequest(meth, url, body: string, headers: openarray[(string, string)]): JsObject =
    let hdrs = cast[seq[(string, string)]](headers)
    var rPrc =
            proc(emitter: JsObject): proc() =
                let oReq = newXMLHTTPRequest()
                var reqListener: proc ()
                reqListener = proc () =
                    jsUnref(reqListener)
                    console.log("resp:", oReq.`type`.toJs, oReq.status.toJs, oReq.statusText.toJs, oReq.responseText.toJs)
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
                console.log("emitter:", emitter)
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


proc login(frmClass: kstring): proc() =
    result = proc() =
        let email = jq("#inputEmail".toJs).val().to(cstring)
        let pass = jq("#inputPassword".toJs).val().to(cstring)
        let frm = jq(frmClass.toJs)
        console.log("clicked ", email, pass)
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
            label:
                input(`type`="checkbox", value="remember-me")
                text " Запомнить меня"
            button(class="btn btn-lg btn-primary btn-block", `type`="submit"#[, onclick = login(".form-signin")]#):
                text "Войти"
            p(class="mt-5 mb-3 text-muted text-center"):
                text "© 2019"

proc createDom(): VNode =
    result = buildHtml tdiv(class = "main-root"):
        if currUser.token == "":
            loginDialog()


setRenderer createDom, "main-control-container"