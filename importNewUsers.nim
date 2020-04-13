import parsecsv, streams, strutils, httpclient, uri, json, random, strformat, asyncdispatch
import src/util/types

randomize()

const
    token = "881d79ceee09f6d86c82f2f1d9f8fd7e"
var  apiKeys = @[
        "в базе паролей"
    ]


var
    outUsers = newSeq[string]()
    outContent = newSeq[Future[string]]()
    parser: CsvParser
    fn = "usersDimaGor.csv"
    strm = newFileStream(fn, fmRead)

parser.open(strm, fn, '|', '0')
## Need calling `readHeaderRow`.
parser.readHeaderRow()
while parser.readRow():
    shuffle apiKeys
    let
        lname = parser.rowEntry("lname").strip
        fname = parser.rowEntry("fname").strip
        c = newHttpClient()
    var uri = initUri()
    uri.scheme = "https"
    uri.hostname = "m2414.de"#"127.0.0.1"
    #uri.port = "5000"
    uri.path = "/user/new"
    uri = uri ? [("firstname", fname), ("lastname", lname), ("role", "user"), ("apiKey", apiKeys[0]), ("token", token)]
    #echo "uri:", $uri
    let 
        respUsrJsn = c.getContent($uri).parseJson()
        #respUsrJsn = c.getContent($uri)
        user = respUsrJsn.to(StatusResp[User]).resp
    #outContent.add respUsrJsn
    outUsers.add &"Имя: {user.firstname} {user.lastname}, Пароль: {user.password}"
    #break
#echo "outUsers:", outUsers
parser.close()
strm.close()

#for oc in outContent:
    #let r = waitFor oc
writeFile("userspassDimaGor.csv", outUsers.join("\n"))