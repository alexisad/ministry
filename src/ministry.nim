import htmlgen
import jester
import db_sqlite, md5, times, random, strutils
import util/types

var db: DbConn

proc dropTbl(n: string) =
  echo "n: ", n
  let rows = db.getAllRows(sql"""SELECT 
          *
          FROM 
          sqlite_master 
          WHERE 
          type ='table' AND 
          name = ?""", n)
  if rows.len != 0:
    db.exec(sql"""DROP TABLE ? """, n)


proc reDb() =
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
            )""")
      db.exec(sql"""CREATE TABLE user (
              id   INTEGER PRIMARY KEY,
              corpus_id  INTEGER NOT NULL,
              firstname VARCHAR(50) NOT NULL,
              lastname VARCHAR(50) NOT NULL,
              email VARCHAR(100) NOT NULL,
              password VARCHAR(100) NOT NULL,
              role_id   INTEGER  NOT NULL,
              FOREIGN KEY (corpus_id)
                REFERENCES corpus (id),
              FOREIGN KEY (role_id)
                REFERENCES role (id)
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

proc login(user, pass: string): bool =
  if pass == "" or user == "":
    return false
  let rowUser = db.getRow(sql"""SELECT 
                *
                FROM 
                user 
                WHERE 
                email = ? AND password= ?""", user, pass.getMD5)
  let user_id = rowUser[0]
  if user_id == "":
    return false
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
    return false
  let rowsToken = db.getAllRows(sql"""SELECT 
                *
                FROM 
                token""")
  echo user, " ", pass, " table token: ", rowsToken
  result = true


proc checkAdmin(t: string): tuple[isAdmin: bool, user: User] =
  let rowUser = db.getRow(sql"""SELECT 
                *
                FROM 
                token 
                WHERE 
                token = ? AND date_activity > ? """, t, now() - 10.minutes)
  let admin_id = rowUser[2]
  let rowAdmin = db.getRow(sql"""SELECT 
                user.id, user.corpus_id, role.id
                FROM user 
                INNER JOIN role on user.role_id = role.id
                WHERE user.id = ? AND role.role ="admin" """, admin_id)
  echo "checkAdmin:: ", rowUser, rowAdmin
  if rowAdmin[0] != "":
    result = (isAdmin: true, user: User(id: rowAdmin[0].parseInt, corpus_id: rowAdmin[1].parseInt))
  else:
    result = (isAdmin: false, user: User())

proc getUser(id: int64): User = 
  let rowU = db.getRow(sql"""SELECT 
          *
          FROM user 
          WHERE id = ?""", id)
  result.id = rowU[0].parseInt
  result.corpus_id = rowU[1].parseInt
  result.firstname = rowU[2]
  result.lastname = rowU[3]
  result.email = rowU[4]
  result.password = rowU[5]
  result.role_id = rowU[6].parseInt

proc addUser(u: User): tuple[isAdded: bool, user: User] =
  echo "addUser:: ", u
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
    result.user = getUser(uId)
    



proc main() =
  db = open("ministry.db", "", "", "")
  echo "db connected!!!!!!!!!!!!!"

  routes:
    get "/":
      reDb()
      resp h1("Hello world")
    #get "/favicon.ico":
      #resp(Http200, [("Content-Type","image/x-icon")], request.matches[0])
    get "/login":
      if not login(@"user", @"pass"):
        halt()
      resp h2 "loged " & @"user" & " " & @"pass"
    get "/user/@action":
      if @"token" == "":
        halt()
      let ifAdmin = checkAdmin(@"token")  
      if not ifAdmin.isAdmin:
        halt()
      if @"action" == "new":
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
        resp h1($ifAdded.user)
      else:
        halt()
    #get "/login/@user/pass=@pass":
      #resp h2 "loged " & @"user" & " " & @"pass"

when isMainModule:
  main()

