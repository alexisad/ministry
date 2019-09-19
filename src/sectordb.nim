import json, db_sqlite, times, strutils, tables, strformat
import util/types

proc uploadSector*(db: DbConn, corpusId: int): bool =
  result = false
  let sectorJsn = parseFile("Büdingen_Exp_2019-09-19T11_04_36+02_00.json")
  db.exec(sql"""VACUUM INTO ?""", "ministry_bkp_$1.db" % ($now()).replace(":", "_") )
  #db.exec(sql"""VACUUM""")
  db.exec(sql"BEGIN")
  for sIntId,v in pairs(sectorJsn):
    var s = Sector(postalCode: v["postalCode"].getStr, pFix: v["pFix"].getInt,
                    city: v["city"].getStr, district: v["district"].getStr
              )
    db.exec(sql"""DELETE FROM sector WHERE sector_internal_id = ? AND corpus_id = ?""", sIntId, corpusId)
    let dbSId = db.tryInsertID(sql"""INSERT INTO sector
        (corpus_id, sector_internal_id, name)
        VALUES(?,?,?)
        """, corpusId, sIntId, s.name)
    when true:
      var linksStreet = initTable[int, string](8)
      for ns, sv in pairs(v["streets"].getFields):
        #echo "street: ", ns
        var lnksGeo = newSeqOfCap[string](sv.len)
        for lnk in sv:
          lnksGeo.add lnk["geometry"].getStr
          let ix = lnk["linkId"].getInt()
          #echo "ix:: ", $ix
          discard linksStreet.hasKeyOrPut(ix, ns)
        db.exec(sql"""INSERT INTO street
                (sector_id, name, geometry)
                VALUES(?,?,?)
          """, dbSId, ns, lnksGeo.join ";")
      for ns, sv in pairs(v["streets"].getFields):
        for lnk in sv:
          let strRow = db.getRow(sql"""SELECT id FROM street
                  WHERE name = ? AND sector_id = ?""",
                    ns, dbSId)
          if strRow[0] == "":
            echo "strRow[0] not found"
          for nLnk in lnk["neighborLinks"].getElems:
            let pnLnk = abs(nLnk.getInt)
            if linksStreet.hasKey pnLnk:
              #echo "nLnk found: ", nLnk.getInt
              let strNRow = db.getRow(sql"""SELECT id FROM street
                        WHERE name = ? AND sector_id = ?""",
                            linksStreet[pnLnk], dbSId)
              if strNRow[0] == "":
                echo "strNRow[0] not found"
              let strBRow = db.getRow(sql"""SELECT id FROM rame
                          WHERE street_id = ? AND rame_street_id = ?""",
                              strRow[0], strNRow[0])
              if strBRow[0] == "":
                db.exec(sql"""INSERT INTO rame
                          (street_id, rame_street_id)
                              VALUES(?,?)
                      """, strRow[0], strNRow[0])
  if not db.tryExec(sql"COMMIT"):
    db.exec(sql"ROLLBACK")
    return false
      
  result = true