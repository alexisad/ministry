import utiljs
import karax / [karaxdsl, karax, vdom, jstrutils]
#import karax / [vstyles]
import jsffi except `&`
#import jsbind
import async_http_request#, asyncjs
#from sugar import `=>`, `->`
#from uri import decodeUrl
import src/util/types
import strformat, strutils, uri

proc editUsers*(): proc()

proc chgUser(u: User): proc() = 
    result = proc() =
        var edU = u
        let
            cntr = ".list-users .frm" & $u.id
            inpFirstNameId = cstring [cntr, "#inputFirstName" & $u.id].join" "
            inpLastNameId = cstring [cntr, "#inputLastName" & $u.id].join" "
            inpApiKeyId = cstring [cntr, "#inpApiKey" & $u.id].join" "
        edU.firstName = $jq(inpFirstNameId.toJs)[0].value.to(cstring)
        edU.lastName = $jq(inpLastNameId.toJs)[0].value.to(cstring)
        edU.apiKey = $jq(inpApiKeyId.toJs)[0].value.to(cstring)
        let uName = [edU.firstName, edU.lastName].join" "
        dbg: console.log(cstring"User", u, edU)
        let
            uNameEnc =  uName.encodeUrl()
            firstNameEnc = edU.firstName.encodeUrl()
            lastNameEnc = edU.lastName.encodeUrl()
            apiKeyEnc = edU.apiKey.encodeUrl()
        let updStm = sendRequest(
            "GET",
            &"/user/update?id={u.id}&email={uNameEnc}&firstname={firstNameEnc}" &
                &"&apiKey={apiKeyEnc}&lastname={lastNameEnc}&token={currUser.token}"
        )
        updStm.observe(
            proc (value: Response) =
                dbg: console.log("value:", value.statusCode, value)
                let respUser = parseResp(value.body, StatusResp[User])
                let respU = respUser.resp
                errMsg = $respUser.message
                for i,u in allUsers:
                    if u.id == respU.id:
                        allUsers[i] = respU
                        break
                redraw()
            ,
            proc (error: Response) =
                console.log("error:", error.statusCode)
        )

proc showUsers*(): VNode =
    result = buildHtml tdiv(class="accordion list-users", id="accordionUsers"):
        for u in allUsers:
            let
                headingId = ("heading" & $u.id).cstring
                collapseId = ("collapse" & $u.id).cstring
                uName = [u.firstname, u.lastname].join" "
                inpFirstNameId = ("inputFirstName" & $u.id).cstring
                inpLastNameId = ("inputLastName" & $u.id).cstring
                inpApiKeyId = ("inpApiKey" & $u.id).cstring
                frmId = ("frm" & $u.id).cstring
            tdiv(class="card"):
                tdiv( class="card-header", id = headingId):
                    h2(class="mb-0"):
                        button(class="btn btn-link collapsed", `type`="button", data-toggle="collapse",
                                        data-target="#" & collapseId, aria-expanded="false", aria-controls = collapseId):
                            text uName
            tdiv(id = collapseId, class="collapse", aria-labelledby = headingId, data-parent="#accordionUsers"):
                tdiv(class="card-body"):
                    tdiv(class="form " & frmId):
                        tdiv(class="form-group"):
                            label(`for` = inpFirstNameId):
                                text "Имя"
                            input(`type`="text", class="form-control", id = inpFirstNameId, placeholder="Имя", value = u.firstname.cstring)
                        tdiv(class="form-group"):
                            label(`for` = inpLastNameId):
                                text "Фамилия"
                            input(`type`="text", class="form-control", id = inpLastNameId, placeholder="Фамилия", value = u.lastname.cstring)
                        tdiv(class="form-group"):
                            label(`for` = inpApiKeyId):
                                text "apiKey"
                            input(`type`="text", class="form-control", id = inpApiKeyId, placeholder="HERE apiKey", value = u.apiKey.cstring)
                        if u.password != "":
                            tdiv(class="form-group"):
                                span():
                                    text &"Пароль: {u.password}" 
                        tdiv(class="form-group"):
                            button(`type`="button", class="btn btn-success", onclick = chgUser(u)):
                                text "Обновить"

proc editUsers*(): proc() = 
    result = proc() =
        let rStm = sendRequest(
            "GET",
            "/user/list?" & &"token={currUser.token}"
        )
        rStm.observe(
            proc (value: Response) =
                dbg: console.log("value body:", value.statusCode, $(value.body))
                let respUsers = parseResp($(value.body), StatusResp[seq[User]])
                errMsg = $respUsers.message
                allUsers = respUsers.resp
                isShowUsers = true
                redraw()
            ,
            proc (error: Response) =
                console.log("error:", error.statusCode)
        )

