import htmlgen
import jester
import db_sqlite, md5, times, random, strutils, json
import util/types

var db*: DbConn


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
    dropTbl "sector"
    db.exec(sql"""CREATE TABLE sector (
              sector_id  INTEGER PRIMARY KEY,
              corpus_id  INTEGER NOT NULL,
              sector_internal_id INTEGER NOT NULL,
              name VARCHAR(100) NOT NULL,
              FOREIGN KEY (corpus_id)
                REFERENCES corpus (id)
                  ON UPDATE CASCADE
                  ON DELETE RESTRICT
            )""")
    dropTbl "street"
    db.exec(sql"""CREATE TABLE street (
              id   INTEGER PRIMARY KEY,
              name VARCHAR(500) NOT NULL,
              sector_id INTEGER NOT NULL,
              geometry TEXT,
              FOREIGN KEY (sector_id)
                REFERENCES sector (sector_id)
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
  when false:
    when true:
      dropTbl "corpus"
      dropTbl "role"
      dropTbl "token"
      dropTbl "user"
    when true:
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
              corpus_id  INTEGER NOT NULL,
              firstname VARCHAR(50) NOT NULL,
              lastname VARCHAR(50) NOT NULL,
              email VARCHAR(100) UNIQUE NOT NULL,
              password VARCHAR(100) NOT NULL,
              role_id   INTEGER  NOT NULL,
              FOREIGN KEY (corpus_id)
                REFERENCES corpus (id)
                  ON UPDATE CASCADE
                  ON DELETE RESTRICT,
              FOREIGN KEY (role_id)
                REFERENCES role (id)
                  ON UPDATE CASCADE
                  ON DELETE RESTRICT
            )""")
      db.exec(sql"""INSERT into user (corpus_id, firstname, lastname, email, password, role_id)
              VALUES(?,?,?,?,?,?)
            """, 1, "Alexander", "Sadovoy", "sadovoyalexander@yahoo.de", "698d51a19d8a121ce581499d7b701668", 1)
    let rows = db.getAllRows(sql"""SELECT 
                  *
                  FROM 
                  sqlite_master 
                  WHERE 
                  type ='table' AND 
                  name NOT LIKE 'sqlite_%'""")
    for row in rows:
      echo row
    echo "++++++++++ ", "111".toMD5, " ", "111".getMD5

proc login(user, pass: string): tuple[isOk: bool, user: User, token: string] {.gcsafe.} =
  result.isOk = false
  if pass == "" or user == "":
    return result
  let rowUser = db.getRow(sql"""SELECT 
                *
                FROM 
                user 
                WHERE 
                email = ? AND password= ?""", user, pass.getMD5)
  let user_id = rowUser[0]
  if user_id == "":
    return result
  randomize()
  db.exec(sql"BEGIN")
  db.exec(sql"""DELETE FROM 
                token 
                WHERE 
                user_id = ?""", user_id)
  var idChs = $IdentChars
  shuffle(idChs)
  let token = getMD5(user_id & idChs & $now())
  db.exec(sql"""INSERT into token (token, user_id, date_activity)
              VALUES(?,?,?)
            """, token, user_id, $now())
  if not db.tryExec(sql"COMMIT"):
    db.exec(sql"ROLLBACK")
    return result
  let rowsToken = db.getAllRows(sql"""SELECT 
                *
                FROM 
                token""")
  #echo user, " ", pass, " table token: ", rowsToken
  {.gcsafe.}:
    let u = getUser user_id.parseInt
  if not u.isOk:
    return result
  result = (isOk: true, user: u.user, token: token)

proc checkToken(t: string): tuple[isOk: bool, rowToken: Row] =
  let rowToken = db.getRow(sql"""SELECT 
                *
                FROM 
                token 
                WHERE 
                token = ? AND date_activity > ? """, t, $(now() - 10.minutes))
  if rowToken[2] == "":
    result.isOk = false
    return result
  db.exec(sql"""UPDATE token
    SET date_activity = ?
    WHERE token = ?""", $now(), t)
  (isOk: true, rowToken: rowToken)

proc checkAdmin(t: string): tuple[isAdmin: bool, user: User] =
  let rChck = checkToken(t)
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

proc row2User(rowU: Row, showPass = false): User =
  result.id = rowU[0].parseInt
  result.corpus_id = rowU[1].parseInt
  result.firstname = rowU[2]
  result.lastname = rowU[3]
  result.email = rowU[4]
  if showPass:
    result.password = rowU[5]
  result.role_id = rowU[6].parseInt

proc getUser(id: int64, showPass = false): tuple[isOk: bool, user: User] = 
  result.isOk = false
  let rowU = db.getRow(sql"""SELECT 
          *
          FROM user 
          WHERE id = ?""", id)
  if rowU[0] == "":
    return result
  result = (isOk: true, user: row2User(rowU, showPass))



proc addUser(u: User): tuple[isAdded: bool, user: User] =
  #echo "addUser:: ", u
  let addF = (isAdded: false, user: User())
  if u.firstname == "" or u.lastname == "" or u.email == "" or u.role == "":
    return addF
  else:
    let rowU = db.getRow(sql"""SELECT 
                count(*)
                FROM user 
                WHERE email = ?""", u.email)
    if rowU[0].parseInt > 0:
      return addF
    let rowRole = db.getRow(sql"""SELECT 
                role.id
                FROM role 
                WHERE role = ?""", u.role)
    if rowRole[0] == "":
      return addF
    db.exec(sql"BEGIN")
    let uId = db.tryInsertID(sql"""INSERT into user (corpus_id, firstname, lastname, email, password, role_id)
              VALUES(?,?,?,?,?,?)
            """, u.corpus_id, u.firstname, u.lastname, u.email, u.password.getMD5, rowRole[0])
    if uId == -1 or not db.tryExec(sql"COMMIT"):
      db.exec(sql"ROLLBACK")
      return addF
    result.isAdded = true
    let u = getUser(uId)
    if not u.isOk:
      return addF
    result.user = u.user


proc getUser(t, e: string): tuple[isOk: bool, user: User] =
  let rChck = checkToken(t)
  if not rChck.isOk:
    return (isOk: false, user: User())
  let rowU = db.getRow(sql"""SELECT 
          *
          FROM user 
          WHERE email = ?""", e)
  if rowU[0] == "":
    return (isOk: false, user: User())
  result = (isOk: true, user: row2User rowU)

proc delUser(e: string): bool =
  db.exec(sql"BEGIN")
  db.exec(sql"""DELETE FROM user WHERE email = ?""", e)
  if not db.tryExec(sql"COMMIT"):
    db.exec(sql"ROLLBACK")
    return false
  result = true

proc updUser(id, firstname, lastname, email, password, role_id: string): bool =
  if id == "":
    return false
  var u = getUser(id.parseBiggestInt, true)
  if not u.isOk:
    return false
  var user = u.user
  if firstname != "":
    user.firstname = firstname
  if lastname != "":
    user.lastname = lastname
  if email != "":
    user.email = email
  if password != "":
    user.password = password.getMD5
  if role_id != "":
    user.role_id = role_id.parseInt
  #echo "updUser: ", $u
  db.exec(sql"BEGIN")
  db.exec(sql"""UPDATE user
    SET firstname = ?,
      lastname = ?,
      email = ?,
      password = ?,
      role_id = ?
    WHERE id = ?""",
      user.firstname, user.lastname, user.email,
      user.password, user.role_id, id
    )
  if not db.tryExec(sql"COMMIT"):
    db.exec(sql"ROLLBACK")
    return false
  result = true

  
template checkAdminToken(ifAdmin: untyped): untyped =
  if @"token" == "":
    halt()
  let ifAdmin = checkAdmin(@"token")  
  if not ifAdmin.isAdmin:
    halt()

import sectordb

proc main() =
  db = open("ministry.db", "", "", "")
  db.exec(sql"PRAGMA foreign_keys = ON")
  echo "db connected!!!!!!!!!!!!!"

  routes:
    get "/":
      reDb()
      resp h1("Hello world")
    #get "/favicon.ico":
      #resp(Http200, [("Content-Type","image/x-icon")], request.matches[0])
    get "/login":
      let logged = login(@"email", @"pass")
      if not logged.isOk:
        halt()
      #resp h2 "logged " & $logged.user & logged.token
      resp Http200, [("Content-Type","application/json")], $(%*{"token": logged.token})
    get "/user/@action":
      if @"action" == "new":
        checkAdminToken ifAdmin
        let ifAdded = addUser User(
                  firstname: strip(@"firstname"),
                  lastname: strip(@"lastname"),
                  email: strip(@"email"),
                  role: strip(@"role"),
                  corpus_id: ifAdmin.user.corpus_id,
                  password: strip(@"password")
                )
        if not ifAdded.isAdded:
          halt()
        #resp h1($ifAdded.user)
        resp Http200, [("Content-Type","application/json")], $(%*ifAdded.user)
      elif @"action" == "delete":
        checkAdminToken ifAdmin
        if not delUser @"email":
          halt()
        #resp h3 "tokens: " & $getTblRows("token") & "<br/>users: " & $getTblRows("user")
        resp Http200, [("Content-Type","application/json")], $(%*{"status": true})
      elif @"action" == "get":
        let rU = getUser(@"token", @"email")
        if not rU.isOk:
          halt()
        #resp h4 "user: " & $(%*rU.user)
        resp Http200, [("Content-Type","application/json")], $(%*rU.user)
      elif @"action" == "update":
        #resp h4 "boo: "
        checkAdminToken ifAdmin
        if not updUser(@"id", @"firstname", @"lastname", @"email", @"password", @"role_id"):
          halt()
        let rU = getUser(@"id".parseInt)
        resp h4 "user: " & $rU
      else:
        halt()
    get "/sector/@action":
      if @"action" == "upload":
        checkAdminToken ifAdmin
        if not uploadSector(db, ifAdmin.user.corpus_id):
          halt()
        #echo $getTblRows("sector")
        resp Http200, [("Content-Type","application/json")], $(%*{"status": true})
      else:
        halt()
when isMainModule:
  main()

