# nimble build --stackTrace:off --threads:on --opt:speed -d:noSignalHandler -d:release --cpu:amd64 --os:linux --compileOnly --genScript
#import htmlgen
import asyncdispatch, jester
import std / [times, random, strutils, json]
import checksums/md5
import db_connector/db_sqlite
from uri import encodeUrl
import posix#, sdnotify
import util/types
import util/utils
import sectordb

#[onSignal(SIGABRT):
  ## Handle SIGABRT from systemd
  # Lines printed to stdout will be received by systemd and logged
  # Start with "<severity>" from 0 to 7
  echo "<2>Received SIGABRT"
  quit(1)]#

when false:
  let sd = newSDNotify()
  sd.notify_ready()
  # Every 5 seconds in a dedicated thread:
  sd.ping_watchdog()

var db*: DbConn

include "../index31.html.nimf"

proc getUser(id: int64, showPass = false): tuple[isOk: bool, user: User]

proc dropTbl(n: string) =
  #echo "n: ", n
  let rows = db.getAllRows(sql"""SELECT 
          *
          FROM 
          sqlite_master 
          WHERE 
          type ='table' AND 
          name = ?""", n)
  if rows.len != 0:
    db.exec(sql"""DROP TABLE ? """, n)


proc getTblRows(n: string): seq[Row] =
  result = db.getAllRows(sql"""SELECT
            *
            FROM 
            ?""", n)


proc reDb() =
  when true:
    when true:
      dropTbl "corpus"
      dropTbl "role"
      dropTbl "token"
      dropTbl "user"
    when false:
      db.exec(sql"""CREATE TABLE corpus (
              id   INTEGER PRIMARY KEY,
              name VARCHAR(50) NOT NULL
            )""")
      db.exec(sql"""INSERT into corpus (name)
              VALUES(?)
            """, "Hanau-Russisch")
      db.exec(sql"""CREATE TABLE role (
              id   INTEGER PRIMARY KEY,
              role VARCHAR(20) NOT NULL
            )""")
      db.exec(sql"""INSERT into role (role)
              VALUES(?)
            """, "superadmin")
      db.exec(sql"""INSERT into role (role)
              VALUES(?)
            """, "admin")
      db.exec(sql"""INSERT into role (role)
              VALUES(?)
            """, "user")
      db.exec(sql"""CREATE TABLE token (
              id   INTEGER PRIMARY KEY,
              token VARCHAR(10) NOT NULL,
              user_id   INTEGER  NOT NULL,
              date_activity TEXT,
              FOREIGN KEY (user_id)
                REFERENCES user (id)
                  ON UPDATE CASCADE
                  ON DELETE CASCADE
            )""")
      db.exec(sql"""CREATE TABLE user (
              id   INTEGER PRIMARY KEY,
              corpus_id INTEGER NOT NULL,
              firstname VARCHAR(50) NOT NULL,
              lastname VARCHAR(50) NOT NULL,
              email VARCHAR(100) UNIQUE NOT NULL,
              password VARCHAR(100) NOT NULL,
              role_id   INTEGER  NOT NULL,
              active INTEGER NOT NULL,
              api_key VARCHAR(100) NOT NULL,
              FOREIGN KEY (corpus_id)
                REFERENCES corpus (id)
                  ON UPDATE CASCADE
                  ON DELETE RESTRICT,
              FOREIGN KEY (role_id)
                REFERENCES role (id)
                  ON UPDATE CASCADE
                  ON DELETE RESTRICT
            )""")
      db.exec(sql"""INSERT into user (corpus_id, firstname, lastname, email, password, role_id, active, api_key)
              VALUES(?,?,?,?,?,?,?,?)
            """, 1, "Alexander", "Sadovoy", "alexander.sadovoy@m2414.de", "698d51a19d8a121ce581499d7b701668", 1, 1, "")
    let rows = db.getAllRows(sql"""SELECT 
                  *
                  FROM 
                  sqlite_master 
                  WHERE 
                  type ='table' AND 
                  name NOT LIKE 'sqlite_%'""")
    dbg:
      for row in rows:
        echo row
      echo "++++++++++ ", "111".toMD5, " ", "111".getMD5
  block x1:
    when false:
      dropTbl "sector"
      db.exec(sql"""CREATE TABLE sector (
                  id INTEGER PRIMARY KEY,
                  corpus_id  INTEGER NOT NULL,
                  sector_internal_id INTEGER NOT NULL,
                  name VARCHAR(100) NOT NULL,
                  plz VARCHAR(15) NOT NULL,
                  pfix INTEGER NOT NULL,
                  inactive INTEGER NOT NULL,
                FOREIGN KEY (corpus_id)
                  REFERENCES corpus (id)
                    ON UPDATE CASCADE
                    ON DELETE RESTRICT
              )""")
      db.exec(sql"""CREATE INDEX idx_corp_sector
              ON sector (corpus_id, sector_internal_id)
            """)
      dropTbl "status_street"
      db.exec(sql"""CREATE TABLE status_street (
                id   INTEGER PRIMARY KEY,
                name VARCHAR(30) NOT NULL
              )""")
      db.exec(sql"""INSERT into status_street (id, name)
          VALUES
            (?,?), (?,?), (?,?)
              """, 0, "strNotStarted", 1, "strStarted", 2, "strFinished")
      dropTbl "street"
      db.exec(sql"""CREATE TABLE street (
                id   INTEGER PRIMARY KEY,
                name VARCHAR(500) NOT NULL,
                sector_id INTEGER NOT NULL,
                status_street_id INTEGER,
                geometry TEXT,
                total_families INTEGER,
                FOREIGN KEY (sector_id)
                  REFERENCES sector (id)
                    ON UPDATE CASCADE
                    ON DELETE CASCADE
              )""")
      dropTbl "rame"
      db.exec(sql"""CREATE TABLE rame (
                id   INTEGER PRIMARY KEY,
                street_id INTEGER NOT NULL,
                rame_street_id INTEGER NOT NULL,
                FOREIGN KEY (street_id)
                  REFERENCES street (id)
                    ON UPDATE CASCADE
                    ON DELETE CASCADE,
                FOREIGN KEY (rame_street_id)
                  REFERENCES street (id)
                    ON UPDATE CASCADE
                    ON DELETE CASCADE
              )""")
  block x2:
    when false:
      dropTbl "ministry_act"
      db.exec(sql"""CREATE TABLE ministry_act (
                id  INTEGER PRIMARY KEY,
                action VARCHAR(25) NOT NULL
              )""")
      db.exec(sql"""INSERT into ministry_act (action)
                  VALUES(?)
              """, "start")
      db.exec(sql"""INSERT into ministry_act (action)
              VALUES(?)
          """, "finish")
      dropTbl "user_sector"
      db.exec(sql"""CREATE TABLE user_sector (
            id  INTEGER PRIMARY KEY,
            sector_id INTEGER NOT NULL,
            user_id INTEGER NOT NULL,
            date_start TEXT NOT NULL,
            date_finish TEXT,
            time_start TEXT NOT NULL,
            time_finish TEXT,
            FOREIGN KEY (sector_id)
                  REFERENCES sector (id)
                    ON UPDATE CASCADE
                    ON DELETE RESTRICT,
            FOREIGN KEY (user_id)
                  REFERENCES user (id)
                    ON UPDATE CASCADE
                    ON DELETE RESTRICT
          )""")
  when false:
    db.exec(sql"""CREATE INDEX idx_usector
              ON user_sector (user_id, sector_id)
            """)
    db.exec(sql"""CREATE INDEX idx_inact
              ON sector (inactive)
            """)
    db.exec(sql"""CREATE INDEX idx_name_sector
              ON street (name, sector_id)
            """)
    db.exec(sql"""CREATE INDEX idx_street_rame
            ON rame (street_id, rame_street_id)
          """)

proc parseUserName(un: string): tuple[a: string, b: string] =
  let dn = "@m2414.de"
  var r = un.strip.toLowerAscii
  while true:
    let len = r.len
    r = r.replace(" ".repeat(2), " ")
    if r.len == len:
      break
  let rSeq = r.split" "
  if rSeq.len != 2: return# return empty tuple, name should be from two parts
  result = (a: rseq.join"." & dn, b: [rSeq[1], rSeq[0]].join"." & dn)
  dbg: echo "parseUserName:", result


proc login(user, pass: string): tuple[isOk: bool, user: User, token: string] {.gcsafe.} =
  result.isOk = false
  if pass == "" or user == "":
    return result
  #let twoUsName = parseUserName user
  let pMD5 = pass.getMD5
  #[let rowUser = db.getRow(sql"""SELECT 
                *
                FROM 
                user 
                WHERE 
                (email = ? AND password= ?) OR (email = ? AND password= ?)""",
                  twoUsName[0], pMD5, twoUsName[1], pMD5)]#
  let rowUser = db.getRow(sql"""SELECT 
                *
                FROM 
                user 
                WHERE 
                password= ?""",
                  pMD5)
  let user_id = rowUser[0]
  if user_id == "":
    return result
  randomize()
  db.exec(sql"BEGIN")
  db.exec(sql"""DELETE FROM 
                token 
                WHERE 
                user_id = ?""", user_id)
  var idChs = PasswordLetters
  shuffle(idChs)
  let token = getMD5(user_id & idChs & $now())
  db.exec(sql"""INSERT into token (token, user_id, date_activity)
              VALUES(?,?,?)
            """, token, user_id, $now())
  if not db.tryExec(sql"COMMIT"):
    db.exec(sql"ROLLBACK")
    return result
  #[let rowsToken = db.getAllRows(sql"""SELECT 
                *
                FROM 
                token""")
  #echo user, " ", pass, " table token: ", rowsToken]#
  {.gcsafe.}:
    let u = getUser user_id.parseInt
  if not u.isOk:
    return result
  result = (isOk: true, user: u.user, token: token)

proc checkAdmin(t: string): tuple[isAdmin: bool, user: User] =
  let rChck = checkToken(db, t)
  if not rChck.isOk:
    return (isAdmin: false, user: User())
  let rowToken = rChck.rowToken
  let admin_id = rowToken[2]
  let rowAdmin = db.getRow(sql"""SELECT 
                user.id, user.corpus_id, role.id
                FROM user 
                INNER JOIN role on user.role_id = role.id
                WHERE user.id = ? AND (role.role ="admin" OR role.role ="superadmin") """, admin_id)
  #echo "checkAdmin:: ", rowToken, rowAdmin
  if rowAdmin[0] != "":
    result = (isAdmin: true, user: User(id: rowAdmin[0].parseInt, corpus_id: rowAdmin[1].parseInt))
  else:
    result.isAdmin = false


proc getUser(id: int64, showPass = false): tuple[isOk: bool, user: User] = 
  result.isOk = false
  let rowU = db.getRow(sql"""SELECT 
          user.*, role.role
          FROM user, role 
          WHERE user.role_id = role.id AND user.id = ?""", id)
  if rowU[0] == "":
    return result
  result = (isOk: true, user: row2User(rowU, showPass))

proc getUser(uName: string): tuple[isOk: bool, user: User] = 
  result.isOk = false
  let twoUsName = parseUserName uName
  let rowU = db.getRow(sql"""SELECT 
                user.*, role.role
                FROM user, role 
                WHERE 
                user.role_id = role.id AND (email = ? OR email = ?)""",
                  twoUsName[0], twoUsName[1])
  if rowU[0] == "":
    return result
  result = (isOk: true, user: row2User(rowU))



proc addUser(u: User): StatusResp[User] =
  dbg: echo "addUser:: ", u
  result.ts = toUnix getTime()
  result.status = stUnknown
  #if u.firstname == "" or u.lastname == "" or u.email == "" or u.role == "":
  if u.role == "":
    return result
  else:
    let rowU = db.getRow(sql"""SELECT 
                count(*)
                FROM user 
                WHERE password = ?""", u.password.getMD5)
    if rowU[0].parseInt > 0:
      result.message = "With the same pass exists already the user, repeat please again"
      return result
    let rowRole = db.getRow(sql"""SELECT 
                role.id
                FROM role 
                WHERE role = ?""", u.role)
    if rowRole[0] == "":
      return result
    db.exec(sql"BEGIN")
    let uId = db.tryInsertID(sql"""INSERT into user (corpus_id, firstname, lastname, email, password, role_id, active, api_key)
              VALUES(?,?,?,?,?,?,?,?)
            """, u.corpus_id, u.firstname, u.lastname, u.email, u.password.getMD5, rowRole[0], 1, u.apiKey)
    if uId == -1:
      db.exec(sql"ROLLBACK")
      return result
    result.status = stOk
    var usr = getUser(uId)
    usr.user.password = u.password
    if not usr.isOk:
      db.exec(sql"ROLLBACK")
      result.status = stUnknown
      return result
    if not db.tryExec(sql"COMMIT"):
      db.exec(sql"ROLLBACK")
      result.status = stUnknown
      return result
    result.resp = usr.user


proc getUser(t, e: string): StatusResp[User] =
  result.ts = toUnix getTime()
  result.status = stUnknown
  var rChck: tuple[isOk: bool, rowToken: Row]
  resultCheckToken(db, t)
  let rowU = db.getRow(sql"""SELECT
          user.*, role.role
          FROM user, role 
          WHERE user.role_id = role.id AND email = ?""", e)
  if rowU[0] == "":
    return result
  result.status = stOk
  result.resp = row2User rowU

proc delUser(e: string): StatusResp[int] =
  result.ts = toUnix getTime()
  result.status = stUnknown
  db.exec(sql"BEGIN")
  if not db.tryExec(sql"""DELETE FROM user WHERE email = ?""", e):
    db.exec(sql"ROLLBACK")
    return result
  if not db.tryExec(sql"COMMIT"):
    db.exec(sql"ROLLBACK")
    return result
  result.status = stOk

proc updUser(id, firstname, lastname, email, password, role_id, active, apiKey: string): StatusResp[User] =
  result.ts = toUnix getTime()
  result.status = stUnknown
  var u =
    if id == "":
      #getUser(email)
      result.message = "Why no id? strange..."
      return result
    else:
      getUser(id.parseBiggestInt, true)
  if not u.isOk:
    return result
  var user = u.user
  var pass: string
  while(true):
    genPassword(pass)
    let rowU = db.getRow(sql"""SELECT 
                  count(*)
                  FROM user 
                  WHERE password = ?""", pass.getMD5)
    if rowU[0].parseInt == 0:
      break
  if firstname != "":
    user.firstname = firstname
  if lastname != "":
    user.lastname = lastname
  #if email != "":
    #user.email = email
  user.password = pass.getMD5
  if role_id != "":
    user.role_id = role_id.parseInt
  if active != "":
    user.active = active.parseInt
  if apiKey != "":
    user.apiKey = apiKey
  db.exec(sql"BEGIN")
  if not db.tryExec(sql"""UPDATE user
          SET firstname = ?,
            lastname = ?,
            email = ?,
            password = ?,
            role_id = ?,
            active = ?,
            api_key = ?
          WHERE id = ?""",
            user.firstname, user.lastname, ($result.ts).getMD5#[[user.firstname, user.lastname].join".".toLowerAscii() & "@m2414.de"]#,
            user.password, user.role_id, user.active, user.apiKey, user.id
        ):
    db.exec(sql"ROLLBACK")
    return result
  var rU = getUser(user.id)
  rU.user.password = pass
  if not rU.isOk:
    db.exec(sql"ROLLBACK")
    return result
  if not db.tryExec(sql"COMMIT"):
    db.exec(sql"ROLLBACK")
    return result
  dbg: echo "updUser: ", user
  result.status = if rU.isOk: stOk else: stUnknown
  result.resp = rU.user

  
template checkAdminToken(ifAdmin: untyped): untyped =
  if @"token" == "":
    halt()
  let ifAdmin = checkAdmin(@"token")
  if not ifAdmin.isAdmin:
    halt()



router mrouter:
  head "/":
    resp(Http200)
  get "/":
    #reDb()
    let cook = request.cookies
    var token: string
    if cook.hasKey "token":
      token = request.cookies["token"]
      if not checkToken(db, token).isOk:
        token = ""
    #let rU = getUser(token, @"email")
    resp(Http200, [("Content-Type","text/html")], genMainPage(token))
    #resp h1("Hello world")
  post "/":
    let logged = login(@"email", @"pass")
    if not logged.isOk:
      if @"test" == "1":
        halt()
      else:
        resp(Http200, [("Content-Type","text/html")], genMainPage())
    let rU = getUser(logged.token, logged.user.email)
    setCookie("token", logged.token, expires=daysForward(5), path="/", #[sameSite=Strict, secure=true, domain="www.alexsad.org"]#)
    resp(Http200, genMainPage(logged.token, encodeUrl $(%*rU)))
  get "/favicon.ico":
    resp(Http200, [("Content-Type","image/x-icon")], request.matches[0])
  get "/user/@action":
    if @"action" == "new":
      checkAdminToken ifAdmin
      #let email = parseUserName([@"firstname", @"lastname"].join" ")
      var pass: string
      genPassword(pass, @"pass")
      let ifAdded = addUser User(
                firstname: "", #strip(@"firstname"),
                lastname: "", #strip(@"lastname"),
                email: ($(toUnix getTime())).getMD5, #email[0],
                role: strip(@"role"),
                corpus_id: ifAdmin.user.corpus_id,
                password: pass,
                apiKey: strip(@"apiKey")
              )
      #if not ifAdded.isAdded:
        #halt()
      #resp h1($ifAdded.user)
      resp $(%*ifAdded)
    elif @"action" == "delete":
      checkAdminToken ifAdmin
      let email = parseUserName(@"email")
      let status = delUser email[0]
      #resp h3 "tokens: " & $getTblRows("token") & "<br/>users: " & $getTblRows("user")
      resp Http200, [("Content-Type","application/json")], $(%*status)
    elif @"action" == "get":
      let email = parseUserName(@"email")
      let rU = getUser(@"token", email[0])
      #if not rU.isOk:
        #halt()
      #resp h4 "user: " & $(%*rU.user)
      resp Http200, [("Content-Type","application/json")], $(%*rU)
    elif @"action" == "list":
      checkAdminToken ifAdmin
      let rUs = getUserList(db, ifAdmin.user.corpus_id)
      resp Http200, [("Content-Type","application/json")], $(%*rUs)
    elif @"action" == "update":
      #resp h4 "boo: "
      checkAdminToken ifAdmin
      var pass: string
      genPassword(pass, @"pass")
      let updU = updUser(@"id", @"firstname", @"lastname", @"email", pass, @"role_id", @"active", @"apiKey")
      resp Http200, [("Content-Type","application/json")], $(%*updU)
    else:
      halt()
  get "/sector/@action":
    if @"action" == "upload":
      checkAdminToken ifAdmin
      let resp = db.uploadSector(corpusId = ifAdmin.user.corpus_id,
                  admName = @"admName",
                  userId = (@"userId").parseInt,
                  fromDate = @"fromDate",
                  toDate = @"toDate"
              )
      #if resp.status == false:
        #halt()
      #echo $getTblRows("sector")
      resp Http200, [("Content-Type","application/json")], $(%*resp)
    elif @"action" == "process":
      let sectProcess = getSectProcess(db, @"token", @"sectorId", @"userId", @"sectorName", @"streetName", @"inactive")
      #if sectProcess.status == false:
        #halt()
      resp %*sectProcess
    elif @"action" == "streets":
      let sectStreets = getSectStreets(db, @"token", @"sectorId")
      resp %*sectStreets
    elif @"action" == "setFamCount":
      checkAdminToken ifAdmin
      resp %*{"success": db.setFamCount()}
    else:
      halt()
  get "/streets/status/@action":
    if @"action" == "update":
      let res = setStatusStreets(db, @"token", @"streets")
      resp %*res
    else:
      halt()
  get "/sector/process/@action":
    if @"action" == "new":
      if @"userId" != "" or @"startDate" != "":
        checkAdminToken ifAdmin
      let sectProcess = newSectProcess(db, @"token",
                    @"sectorId", @"userId", @"startDate")
      resp %*sectProcess
    if @"action" == "delete":
      let ifAdmin = checkAdmin(@"token")
      let delStat = delProcess(db, @"token", @"processId", ifAdmin.isAdmin)
      resp Http200, [("Content-Type","application/json")], $(%*delStat)
    elif @"action" == "update":
      if @"startDate" != "" or @"finishDate" != "":
        checkAdminToken ifAdmin
      let updStat = updProcess(db, @"token", @"processId", @"startDate", @"finishDate")
      dbg:
        echo "updStat:: ", updStat
      resp Http200, [("Content-Type","application/json")], $(%*updStat)
    else:
      halt()
  get "/report/@action":
    checkAdminToken ifAdmin
    if @"action" == "processed":
      let listProcessed = processed(db, @"reportFromDate")
      resp Http200, [("Content-Type","application/json")], $(%*listProcessed)
    elif @"action" == "year":
      let txt = yearReportTxt(db, @"toDate")
      resp Http200, [("Content-Type","text/plain; charset=UTF-8")], txt
    elif @"action" == "portfolio":
      let rHtml = portfolio db
      resp Http200, [("Content-Type","text/html; charset=UTF-8")], rHtml
    elif @"action" == "lastprocess":
      let rHtml = lastProcessed db
      resp Http200, [("Content-Type","text/html; charset=UTF-8")], rHtml
    else:
      halt()
proc main() =
  db = open("ministry.db", "", "", "")
  db.exec(sql"PRAGMA foreign_keys = ON")
  dbg:
    echo "db connected!!!!!!!!!!!!!"
  let settings = newSettings(port = Port(5000))
  var jester = initJester(mrouter, settings=settings)
  jester.serve()


when isMainModule:
  main()

