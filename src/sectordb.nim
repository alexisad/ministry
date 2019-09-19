import json, db_sqlite, times, strutils, tables
import util/types

proc uploadSector*(db: DbConn, corpusId: int): bool =
  result = false
  let sectorJsn = parseFile("Büdingen_Exp_2019-09-17T16_50_06+02_00.json")
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
    echo dbSId
    when true:
      for ns, sv in pairs(v["streets"].getFields):
        echo "street: ", ns
        db.exec(sql"""INSERT INTO street
                (sector_id, name)
                VALUES(?,?)
          """, dbSId, ns)
  if not db.tryExec(sql"COMMIT"):
    db.exec(sql"ROLLBACK")
    return false
      
  result = true