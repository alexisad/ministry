import json, db_sqlite, times, strutils, tables, hashes, parsecsv, streams, unicode
import util/[types, utils]

const normalDateFmt = initTimeFormat("yyyy-MM-dd")

proc hash(x: Street): Hash =
  ## Piggyback on the already available string hash proc.
  ##
  ## Without this proc nothing works!
  #proc uHash(s: string): Hash =
    #result = unicode.toLower(unicode.strip s).hash
  template uHash(s: string): untyped =
    unicode.toLower(unicode.strip s).hash
  result = x.name.uHash !& x.sector.postalCode.uHash !&
      x.sector.city.uHash !& x.sector.district.uHash
  result = !$result

proc initTblTotFamByStreet(): Table[Hash, Natural] =
  result = initTable[Hash, Natural]()
  var
    parser: CsvParser
    fn = "resAllStreets.csv"
    strm = newFileStream(fn, fmRead)

  parser.open(strm, fn, '|', '0')
  ## Need calling `readHeaderRow`.
  parser.readHeaderRow()
  while parser.readRow():
    let strN = parser.rowEntry("Street")
    if strN == "": continue
    let city = parser.rowEntry("City")
    let dstr = parser.rowEntry("District")
    let district =
      if dstr == city:
        ""
      else: dstr
    let sector = Sector(postalCode: parser.rowEntry("Plz"), city: city, district: district)
    let street = Street(name: strN, sector: sector)
    result[street.hash] = parser.rowEntry("TotalFamilies").parseInt
  parser.close()
  strm.close()


proc uploadSector*(db: DbConn, corpusId: int): StatusResp[int] =
  result.status = stUnknown
  let tblTotFam = initTblTotFamByStreet()
  let sectorJsn = parseFile("Büdingen_Exp_2020-03-05T22_27_39+01_00.json")
  db.exec(sql"""VACUUM INTO ?""", "ministry_bkp_$1.db" % ($now()).replace(":", "_") )
  db.exec(sql"BEGIN")
  for sIntId,v in pairs(sectorJsn):
    if v["exclude"].getBool:
      continue
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
        (corpus_id, sector_internal_id, name, inactive, plz, pfix)
        VALUES(?,?,?,0,?,?)
        """, corpusId, sIntId, s.name, s.postalCode, s.pFix)
    var linksStreet = initTable[int, string](8)
    for ns, sv in pairs(v["streets"].getFields):
      #echo "street: ", ns
      var lnksGeo = newSeqOfCap[string](sv.len)
      for lnk in sv:
        lnksGeo.add lnk["geometry"].getStr
        let ix = lnk["linkId"].getInt()
        #echo "ix:: ", $ix
        discard linksStreet.hasKeyOrPut(ix, ns)
      let streetObj = Street(name: ns, sector: s)
      let k = streetObj
      #echo "kkkkkkkkkkkk"
      #echo [k.sector.postalCode, k.sector.city, k.sector.district, k.name].join", "
      let totalFam =
        if tblTotFam.hasKey(streetObj.hash):
          tblTotFam[streetObj.hash]
        else: 0
      db.exec(sql"""INSERT INTO street
              (sector_id, name, geometry, total_families)
              VALUES(?,?,?,?)
        """, dbSId, ns, lnksGeo.join ";", totalFam)
    for ns, sv in pairs(v["streets"].getFields):
      for lnk in sv:
        let strRow = db.getRow(sql"""SELECT id FROM street
                WHERE name = ? AND sector_id = ?""",
                  ns, dbSId)
        #if strRow[0] == "":
          #echo "strRow[0] not found"
        for nLnk in lnk["neighborLinks"].getElems:
          let pnLnk = abs(nLnk.getInt)
          if linksStreet.hasKey pnLnk:
            #echo "nLnk found: ", nLnk.getInt
            let strNRow = db.getRow(sql"""SELECT id FROM street
                      WHERE name = ? AND sector_id = ?""",
                          linksStreet[pnLnk], dbSId)
            #if strNRow[0] == "":
              #echo "strNRow[0] not found"
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
  result.status = stOk


proc getSectProcess*(db: DbConn, t = "", sId = "", uId = "", sName="", inactive = ""): StatusResp[seq[SectorProcess]] =
  result.status = stUnknown
  result.resp = newSeq[SectorProcess]()
  var rChck: tuple[isOk: bool, rowToken: Row]
  resultCheckToken(db, t)
  let vInactive =
    if inactive == "": " AND sector.inactive = 0 " else: inactive
  let vsId =
    if sId != "": (" = ", sId) else: (" <> ", "-1")
  let vuId =
    if uId != "": (" = ", uId) else: (" <> ", "-1")
  let dFinCond =
    if uId != "": "AND user_sector.date_finish is NULL" else: ""
  let vSearchSect =
    if sName != "": "AND sector.name LIKE '%" & sName & "%'" else: ""
  var sqlStr = """SELECT name as sectorName, sector_internal_id, firstname, lastname,
          MAX(date_start), date_finish, user_id,
          sector.id as sector_id, user_sector.id, plz, pfix
          FROM sector
          LEFT JOIN user_sector ON user_sector.sector_id = sector.id {*d_f_c*}
          LEFT JOIN user ON user.id = user_sector.user_id AND user.id *vuId_c* ?
          WHERE
            sector.corpus_id = ?
            {*vInactive*}
            {*v_search_sector*}
            AND sector.id *vsId_c* ?
          GROUP BY sector.id
          ORDER BY date_start ASC, plz, pfix
        """
          .replace("{*vInactive*}", vInactive)
          .replace("*vsId_c*", vsId[0])
          .replace("*vuId_c*", vuId[0])
          .replace("{*d_f_c*}", dFinCond)
          .replace("{*v_search_sector*}", vSearchSect)
  if uId != "":
    sqlStr = sqlStr.replace("LEFT", "")
  dbg:
    echo sId, " -- ", sqlStr
  let sectRows = db.getAllRows(
      sqlStr.sql,
        vuId[1], rChck.rowToken[3], vsId[1] )
  if sectRows.len == 0 or sectRows[0][0] == "":
    return result
  result.status = stOk
  result.resp = newSeqOfCap[SectorProcess](sectRows.len)
  for r in sectRows:
    var sectP = SectorProcess(name: r[0], sector_internal_id: r[1], firstName: r[2], lastName: r[3],
            date_start: r[4], date_finish: r[5],
            user_id: -1, sector_id: r[7].parseInt, id: -1
        )
    if sectP.firstname != "": #someone took this sector
      sectP.user_id = r[6].parseInt
      sectP.id = r[8].parseInt
    result.resp.add sectP

proc newSectProcess*(db: DbConn, t, sId, uId, startDate: string): StatusResp[seq[SectorProcess]] =
  result.status = stUnknown
  var rChck: tuple[isOk: bool, rowToken: Row]
  resultCheckToken(db, t)
  let sDate =
    if startDate != "": startDate else: now().format normalDateFmt
  let sPrRow = db.getRow(sql"""SELECT * FROM user_sector
                  INNER JOIN sector ON user_sector.sector_id = sector.id AND sector.inactive <> 1
                  WHERE
                    sector_id = ? AND
                    (date_finish > ? OR
                    date_finish IS NULL)
                  ORDER BY date_start DESC
            LIMIT 1""", sId, sDate)
  dbg:
    echo "begin insert process: ", [sId, uId, startDate].join(" ")
  if sPrRow[0] != "":
    result.message = "Неудачно: неизвестная ошибка " & $sPrRow
    return result
  let vUid = 
    if uId == "": rChck.rowToken[2]
    else: uId  
  let sPrCntRow = db.getRow(sql"""SELECT count(*) FROM user_sector
        INNER JOIN sector ON user_sector.sector_id = sector.id AND sector.inactive <> 1
        INNER JOIN user ON user.id = user_sector.user_id
        INNER JOIN role ON user.role_id = role.id AND role.role = 'user'
        WHERE user_sector.user_id = ? AND user_sector.date_finish IS NULL""", vUid)
  dbg:
    echo "rChck.rowToken: ", rChck.rowToken
  let cntOnHand = sPrCntRow[0].parseInt
  if cntOnHand >= 4:
    result.message = "Неудачно: на руках больше 4-х участков"
    return result
  dbg:
    echo "begin insert process: ", sPrRow
  db.exec(sql"BEGIN")
  db.exec(sql"""UPDATE street
        SET status_street_id = 0
            WHERE sector_id = ?""",
                sId)
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


proc delProcess*(db: DbConn, t, pId: string): StatusResp[int] =
  result.status = stUnknown
  var rChck: tuple[isOk: bool, rowToken: Row]
  resultCheckToken(db, t)
  var errMsg: string
  let uId = rChck.rowToken[2]
  db.exec(sql"BEGIN")
  try:
    db.exec(sql"""DELETE
          FROM user_sector
            WHERE id = ? AND
              user_id = ?""", pId, uId)
  except:
    errMsg = "Ошибка: " & getCurrentExceptionMsg()
    db.exec(sql"ROLLBACK")
  if errMsg == "":
    if not db.tryExec(sql"COMMIT"):
      db.exec(sql"ROLLBACK")
      return result
    else:
      result.status = stOk
  else:
    result.message = errMsg

proc updProcess*(db: DbConn, t, pId, sDate, fDate: string): StatusResp[seq[SectorProcess]] =
  result.status = stUnknown
  var rChck: tuple[isOk: bool, rowToken: Row]
  resultCheckToken(db, t)
  dbg:
    echo "updProcess:: ", pId
  let sectorPrcRow = db.getRow(sql"""SELECT *
                            FROM user_sector
                            WHERE id = ?
                  """, pId)
  if sectorPrcRow[0] == "":
    result.message = "Процесс обработки " & pId & " не найден"
    return result
  let vsDate = if sDate == "": sectorPrcRow[3] else: sDate
  let vfDate =
    if fDate == "":
      if sectorPrcRow[4] == "":
        now().format normalDateFmt
      else:
        sectorPrcRow[4]
    else:
      fDate
  dbg:
    echo "BEGIN::: ", pId, " ", vsDate, " ", vfDate
  if vsDate > vfDate:
    result.message = "Процесс обработки " & pId & ": дата начала - " & vsDate & " > " & " даты сдачи - " & vfDate
    return result
  db.exec(sql"BEGIN")
  let shOne = db.execAffectedRows(sql"""UPDATE user_sector
          SET date_start = ?,
              date_finish = ?
          WHERE id = ?""",
            vsDate, vfDate, pId)
  if shOne == 0:
    db.exec(sql"ROLLBACK")
    result.message = "Процесс обработки " & pId & " не обновился, причина неизвестна"
    return result
  if not db.tryExec(sql"COMMIT"):
    db.exec(sql"ROLLBACK")
    return result
  let sectorRow = db.getRow(sql"""SELECT sector_id FROM user_sector WHERE id = ?""", pId)
  result = db.getSectProcess(t, sectorRow[0])


proc getSectStreets*(db: DbConn, t, sId: string): StatusResp[seq[SectorStreets]] =
  result.status = stUnknown
  var rChck: tuple[isOk: bool, rowToken: Row]
  resultCheckToken(db, t)
  let streetRows = db.getAllRows(sql"""SELECT 
          s.id, s.name, s.sector_id, status_street.name, s.geometry, s.total_families
          FROM street as s
          LEFT JOIN status_street ON status_street.id = s.status_street_id
          WHERE sector_id = ?""", sId)
  #dbg: echo "streetRows:", streetRows
  for s in streetRows:
    let st = if s[3] != "": s[3] else: "strNotStarted"
    result.resp.add SectorStreets(id: s[0].parseInt,
              name: s[1], sector_id: s[2].parseInt, status: parseEnum[StreetStatus](st),
              geometry: s[4], totalFamilies: s[5].parseInt().Natural)


proc setStatusStreets*(db: DbConn, t, strsStatus: string): StatusResp[int] =
  result.status = stUnknown
  var rChck: tuple[isOk: bool, rowToken: Row]
  resultCheckToken(db, t)
  for str in strsStatus.split(';'):
    let strF = str.split","
    db.exec(sql"""UPDATE street
        SET status_street_id = ?, total_families = ?
            WHERE id = ? AND sector_id = ?""",
            strF[2], strF[3], strF[0], strF[1])
  result.status = stOk
              