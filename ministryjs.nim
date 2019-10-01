# nim -o:public/js/ministry.js js --oldgensym:on --opt:speed -d:release ministry.js.nim
# nim -o:public/js/ministry.js js --debuginfo:on --oldgensym:on ministry.js.nim
# browser-sync start --proxy "http://127.0.0.1:5000" --files "js/*.js"

include karax / prelude
from sugar import `=>`


proc loginDialog(): VNode =
    result = buildHtml form(class="form-signin"):
        tdiv(class="text-center mb-4"):
            h1(class="h3 mb-3 font-weight-normal"):
                text "Войти"
        tdiv(class="form-label-group"):
            input(`type`="email", id="inputEmail", class="form-control", placeholder="Email", required="", autofocus="")
            label(`for`="inputEmail"):
                text "Email"
        tdiv(class="form-label-group"):
            input(`type`="password", id="inputPassword", class="form-control", placeholder="Пароль", required="")
            label(`for`="inputPassword"):
                text "Пароль"
        tdiv(class="checkbox mb-3"):
            label:
                input(`type`="checkbox", value="remember-me")
                text " Запомнить меня"
            button(class="btn btn-lg btn-primary btn-block", `type`="submit"):
                text "Войти"
            p(class="mt-5 mb-3 text-muted text-center"):
                text "© 2019"

proc createDom(): VNode =
    result = buildHtml tdiv(class = "main-root"):
        loginDialog()


setRenderer createDom, "main-control-container"