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


proc getSectProcess*(db: DbConn, t: string): tuple[isOk: bool, sectorProcess: seq[SectorProcess]] =
  result.isOk = false
  result.sectorProcess = newSeq[SectorProcess]()
  let rChck = checkToken(db, t)
  if not rChck.isOk:
    return result
  let sectRows = db.getAllRows(sql"""SELECT name as sectorName, firstname, lastname,
              action, date_start, date_finish, user_id,
              sector.sector_id, act_id
              FROM sector
              LEFT JOIN user_sector ON sector.sector_id = user_sector.sector_id
              LEFT JOIN user ON user_sector.user_id = user.id
              LEFT JOIN ministry_act ON ministry_act.id = user_sector.act_id
              WHERE sector.corpus_id = ?""", rChck.rowToken[3])
  if sectRows.len == 0 or sectRows[0][0] == "":
    return result
  result.isOk = true
  result.sectorProcess = newSeqOfCap[SectorProcess](sectRows.len)
  for r in sectRows:
    var sectP = SectorProcess(name: r[0], firstName: r[1], lastName: r[2],
            action: r[3], date_start: r[4], date_finish: r[5],
            user_id: -1, sector_id: r[7].parseInt, act_id: -1
        )
    if sectP.firstname != "": #someone took this sector
      sectP.user_id = r[6].parseInt
      sectP.act_id = r[8].parseInt
    result.sectorProcess.add sectP

proc newSectProcess*(db: DbConn, t, sId, uId, startDate: string): bool =
  result = false
  let rChck = checkToken(db, t)
  if not rChck.isOk:
    return result
  let sPrRow = db.getRow(sql"""SELECT * FROM user_sector
                  WHERE
                    sector_id = ? AND
                    (date_finish > ? OR
                    date_finish IS NULL)
                  ORDER BY date_start DESC
            LIMIT 1""", sId, startDate)
  if sPrRow[0] != "":
    return result
  db.exec(sql"BEGIN")
  var sqlIns = """INSERT INTO user_sector
          (user_id, act_id, sector_id, date_start)
          VALUES(*??*,
            (SELECT id FROM ministry_act WHERE action = "start"),
            ?, ?
          )"""
  let sPrId =
        if uId != "":
          db.tryInsertID(sqlIns.replace("*??*", "?").sql,
                uId, sId, startDate)
        else:
          db.tryInsertID(sqlIns.replace("*??*", "(SELECT user_id FROM token WHERE token = ?)").sql,
                t, sId, startDate)
  if sPrId == -1 or not db.tryExec(sql"COMMIT"):
    db.exec(sql"ROLLBACK")
    return result
  result = true


proc delProcess*(db: DbConn, t, sId: string): bool =
  result = false