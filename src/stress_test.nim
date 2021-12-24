import harpoon
import std / [json, uri, threadpool, os, random, strformat]

randomize()
let
    token = "960f724dae30485a7a3750d10113cfb9"
    pUri = parseUri(fmt"https://www.m2414.de/sector/process?token={token}&tst=")
    
while true:
    var
        rs = newSeq[FlowVar[JsonNode]]()
        rs2 = newSeq[FlowVar[JsonNode]]()
    for _ in 0..10:
        let sId = rand(1..21)
        let pUri2 = parseUri(fmt"https://www.m2414.de/sector/streets?token={token}&sectorId={sId}&tst=")
        rs.add (spawn pUri.getJson)
        rs2.add (spawn pUri2.getJson)
        #sleep 30

    echo "???:"
    for i, r in rs:
        #echo "i:", i, ":"
        let res2 = ^rs2[i]
        echo "i:", i, ":", (^r).pretty
        echo "i:", i, " res2:", res2.pretty