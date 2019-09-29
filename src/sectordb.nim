import json, db_sqlite, times, strutils, tables
import util/types

proc uploadSector*(db: DbConn, corpusId: int): StatusResp[int] =
  result.status = false
  let sectorJsn = parseFile("Büdingen_Exp_2019-09-19T11_04_36+02_00.json")
  db.exec(sql"""VACUUM INTO ?""", "ministry_bkp_$1.db" % ($now()).replace(":", "_") )
  db.exec(sql"BEGIN")
  for sIntId,v in pairs(sectorJsn):
    var s = Sector(postalCode: v["postalCode"].getStr, pFix: v["pFix"].getInt,
                    city: v["city"].getStr, district: v["district"].getStr
              )
    try:
      db.exec(sql"""DELETE FROM sector WHERE sector_internal_id = ? AND corpus_id = ?""", sIntId, corpusId)
    except:
      if getCurrentExceptionMsg().toUpperAscii().find("CONSTRAINT") != -1:
        stderr.writeLine(getCurrentExceptionMsg())
        db.exec(sql"""UPDATE sector
          SET inactive = 1
          WHERE sector_internal_id = ? AND corpus_id = ?""",
                sIntId, corpusId)
      else:
        db.exec(sql"ROLLBACK")
        return result
    let dbSId = db.tryInsertID(sql"""INSERT INTO sector
        (corpus_id, sector_internal_id, name, inactive)
        VALUES(?,?,?,0)
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
    return result
  result.status = true


proc getSectProcess*(db: DbConn, t = "", sId = "", uId = "", inactive = ""): StatusResp[seq[SectorProcess]] =
  result.status = false
  result.resp = newSeq[SectorProcess]()
  let rChck = checkToken(db, t)
  if not rChck.isOk:
    return result
  let vInactive =
    if inactive == "": " AND sector.inactive = 0 " else: inactive
  let vsId =
    if sId != "": (" = ", sId) else: (" <> ", "-1")
  let vuId =
    if uId != "": (" = ", uId) else: (" <> ", "-1")
  let sqlStr = """SELECT name as sectorName, firstname, lastname,
          date_start, date_finish, user_id,
          sector.id as sector_id, user_sector.id
          FROM sector
          LEFT JOIN user_sector ON user_sector.sector_id = sector.id
          LEFT JOIN user ON user.id = user_sector.user_id
          WHERE
            sector.corpus_id = ?
            {*vInactive*}
            AND sector.id *vsId_c* ?
          ORDER BY date_start
        """
          .replace("{*vInactive*}", vInactive)
          .replace("*vsId_c*", vsId[0])
          .replace("*vuId_c*", vuId[0])
  echo sId, " -- ", sqlStr
  let sectRows = db.getAllRows(
      sqlStr.sql,
          rChck.rowToken[3], vsId[1], vuId[1])
  if sectRows.len == 0 or sectRows[0][0] == "":
    return result
  result.status = true
  result.resp = newSeqOfCap[SectorProcess](sectRows.len)
  for r in sectRows:
    var sectP = SectorProcess(name: r[0], firstName: r[1], lastName: r[2],
            date_start: r[3], date_finish: r[4],
            user_id: -1, sector_id: r[6].parseInt, id: -1
        )
    if sectP.firstname != "": #someone took this sector
      sectP.user_id = r[5].parseInt
      sectP.id = r[7].parseInt
    result.resp.add sectP

proc newSectProcess*(db: DbConn, t, sId, uId, startDate: string): StatusResp[seq[SectorProcess]] =
  result.status = false
  let normalDateFmt = initTimeFormat("yyyy-MM-dd")
  let rChck = checkToken(db, t)
  if not rChck.isOk:
    return result
  let sDate =
    if startDate != "": startDate else: now().format normalDateFmt
  let sPrRow = db.getRow(sql"""SELECT * FROM user_sector
                  WHERE
                    sector_id = ? AND
                    (date_finish > ? OR
                    date_finish IS NULL)
                  ORDER BY date_start DESC
            LIMIT 1""", sId, sDate)
  echo "begin insert process: ", [sId, uId, startDate].join(" ")
  if sPrRow[0] != "":
    return result
  echo "begin insert process: ", sPrRow
  db.exec(sql"BEGIN")
  var sqlIns = """INSERT INTO user_sector
          (user_id, sector_id, date_start)
          VALUES(
            *??*, ?, ?
          )"""
  let sPrId =
        if uId != "":
          db.tryInsertID(sqlIns.replace("*??*", "?").sql,
                uId, sId, sDate)
        else:
          #simple user: check that already > 4 months
          when false:
            let uDate = (now() - 4.months).format normalDateFmt
            let chkDRow = db.getRow(sql"""SELECT * FROM user_sector
                    WHERE
                      user_id = (SELECT user_id FROM token WHERE token = ?) AND
                      sector_id = ? AND
                      date_finish > ?
                    ORDER BY date_finish DESC
                  LIMIT 1""", t, sId, uDate)
            if chkDRow[0] != "":
              db.exec(sql"ROLLBACK")
              return result
          db.tryInsertID(sqlIns.replace("*??*", "(SELECT user_id FROM token WHERE token = ?)").sql,
                t, sId, sDate)
  if sPrId == -1 or not db.tryExec(sql"COMMIT"):
    db.exec(sql"ROLLBACK")
    return result
  result = db.getSectProcess(t, sId)


proc delProcess*(db: DbConn, sId: string): bool =
  result = false

proc updProcess*(db: DbConn, t, pId, uId, sDate, fDate: string): StatusResp[seq[SectorProcess]] =
  result.status = false
  echo "updProcess:: ", pId
  let sectorPrcRow = db.getRow(sql"""SELECT usectB.*
                          FROM user_sector as usectA
                          /*JOIN sector ON sector.inactive = 0*/
                          LEFT JOIN user_sector as usectB
                              ON usectA.sector_id = usectB.sector_id
                          WHERE usectA.id = ?
                          ORDER BY date_start ASC
                  """, pId)
  if sectorPrcRow[0] == "":
    return result
  let vsDate = if sDate == "": sectorPrcRow[3] else: sDate
  let vfDate = if fDate == "": sectorPrcRow[4] else: fDate
  echo "BEGIN::: ", pId, " ", vsDate, " ", vfDate
  if vsDate > vfDate:
    return result
  db.exec(sql"BEGIN")
  let shOne = db.execAffectedRows(sql"""UPDATE user_sector
          SET date_start = ?,
              date_finish = ?
          WHERE id = ?""",
            vsDate, vfDate, pId)
  if shOne == 0:
    db.exec(sql"ROLLBACK")
    return result
  if not db.tryExec(sql"COMMIT"):
    db.exec(sql"ROLLBACK")
    return result
  let sectorRow = db.getRow(sql"""SELECT sector_id FROM user_sector WHERE id = ?""", pId)
  result = db.getSectProcess(t, sectorRow[0])
  