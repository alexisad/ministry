import htmlgen
import jester
import db_sqlite, md5, times

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
  db.exec(sql"BEGIN")
  db.exec(sql"""DELETE FROM 
                token 
                WHERE 
                user_id = ?""", user_id)
  let token = getMD5(user_id & $now())
  db.exec(sql"""INSERT into token (token, user_id, date_activity)
              VALUES(?,?,?)
            """, token, user_id, $now())
  if not db.tryExec(sql"COMMIT"):
    db.exec(sql"ROLLBACK")
    return false
  let rowToken = db.getRow(sql"""SELECT 
                *
                FROM 
                token""")
  echo user, " ", pass, " ", rowToken
  result = true

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
      if @"action" == "new":
        resp h1("try new user")
      else:
        halt()
    #get "/login/@user/pass=@pass":
      #resp h2 "loged " & @"user" & " " & @"pass"

when isMainModule:
  main()

