import std / [json, times, strutils, sequtils, tables, hashes, parsecsv, streams, unicode, strformat, algorithm]
import db_connector/db_sqlite
import util/[types, utils]
import karax / [karaxdsl, vdom]
import flatty, supersnappy

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


proc strTblTotalFamByStreet(): Table[string, Natural] =
  result = initTable[string, Natural]()
  var
    parser: CsvParser
    fn = "resAllStreets.csv"
    strm = newFileStream(fn, fmRead)

  parser.open(strm, fn, '|', '0')
  ## Need calling `readHeaderRow`.
  parser.readHeaderRow()
  while parser.readRow():
    let strN = unicode.strip parser.rowEntry("Street")
    if strN == "": continue
    let city = unicode.strip parser.rowEntry("City")
    let dstr = unicode.strip parser.rowEntry("District")
    let district =
      if dstr == city:
        ""
      else: dstr
    let
      plz = unicode.strip parser.rowEntry("Plz")
    var arrStrAdm = @[plz, city, district, strN]
    if district == "":
      arrStrAdm.delete 2
    let strKey = unicode.toLower(arrStrAdm.join(" "))
    result[strKey] = parser.rowEntry("TotalFamilies").parseInt
  parser.close()
  strm.close()


proc setFamCount*(db: DbConn): bool =
  result = false
  let totalFam = strTblTotalFamByStreet()
  let sectRows = db.getAllRows(sql"""SELECT street.id as street_id, sector.name as sector_adm, street.name as street_name, sector.plz as plz
                                    FROM sector, street
                                    WHERE sector.id = street.sector_id AND inactive = 0 AND corpus_id = 1""")
  db.exec(sql"BEGIN")
  for r in sectRows:
    let
      streetId = r[0]
    var
      arrStrAdm = r[1].split(" ")
    arrStrAdm.delete 0
    arrStrAdm = concat(@[r[3]], arrStrAdm, @[r[2]])
    let strAdm = unicode.toLower arrStrAdm.join(" ")
    #echo "strAdm:", strAdm
    let cntFam =
      if totalFam.hasKey(strAdm):
        #echo "total:", totalFam[strAdm]
        totalFam[strAdm]
      else:
        #echo "not found"
        0
    db.exec(sql"""UPDATE street
      SET total_families = ?
      WHERE id = ?""",
            cntFam, streetId)
  if not db.tryExec(sql"COMMIT"):
    db.exec(sql"ROLLBACK")
    return result
  else:
    result = true
  #for k, v in totalFam:
    #echo "k:", k


proc uploadSector*(db: DbConn, corpusId: int,
                          sData = openFileStream "areaSectors.data",
                          admName: string,
                          userId: int,
                          fromDate: string,
                          toDate: string): StatusResp[int] =
  result.ts = toUnix getTime()
  result.status = stUnknown
  if admName == "" or fromDate == "" or toDate == "" or userId == 0:
    return result
  #let tblTotFam = initTblTotFamByStreet()
  #let sData = openFileStream "areaSectors.data"
  let areaSectors = sData.readAll().uncompress().fromFlatty(AreaSectors)
  let sectInAdmName = areaSectors.sectorsInAdminNames[admName]
  #for sectName in sectInAdmName:
    #result.message &= sectName & ","
  #select sqlite_version()
  #let sqlVerRows = db.getAllRows(sql"""SELECT sqlite_version()""")
  #for r in sqlVerRows:
    #result.message &= r[0] & ","
  #return result
  #let bkpName = "./ministry_bkp_$1.db" % (now().format("yyyy-MM-dd'_'HH'_'mm'_'ss"))
  #db.exec(sql"""VACUUM main INTO ?""", "bkpName")
  #result.message &= "after Vacuum"
  #return result
  db.exec(sql"BEGIN")
  for sectName in sectInAdmName:
    #echo "sectName:", sectName
    let
      pFix = sectName.split" "[0].split"-"[1].parseInt
      sIntId = sectName.split" "[0]
      sector = areaSectors.sectors[sectName]
      postalCode = sector.streets[0].postalCode
      city = sector.streets[0].city
      district = sector.streets[0].district
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
        """, corpusId, sIntId, sectName, postalCode, pFix)
    db.exec(sql"""INSERT INTO user_sector
              (sector_id, user_id, date_start, date_finish, time_start, time_finish)
              VALUES(?,?,?,?,?,?)
        """, dbSId, userId, fromDate, toDate, fromDate, toDate)
    for street in sector.streets:
      let ns = street.street
      var streetCoords = newSeqOfCap[string](street.roadlinks.len)
      for link in street.roadlinks:
        var lnkCoords = newSeqOfCap[string](link.coords.len)
        for p in link.coords:
          lnkCoords.add [p.y, p.x].join","
        streetCoords.add lnkCoords.join","
      let totalFam = 0
      db.exec(sql"""INSERT INTO street
              (sector_id, name, geometry, total_families)
              VALUES(?,?,?,?)
        """, dbSId, ns, streetCoords.join ";", totalFam)

  if not db.tryExec(sql"COMMIT"):
    db.exec(sql"ROLLBACK")
    return result
  result.status = stOk


proc uploadSectorOld*(db: DbConn, corpusId: int): StatusResp[int] =
  result.ts = toUnix getTime()
  result.status = stUnknown
  let tblTotFam = initTblTotFamByStreet()
  let sectorJsn = parseFile("Büdingen_Exp_2020-04-10T23_11_24+02_00.json")
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


proc getSectProcess*(db: DbConn, t = "", sId = "", uId = "", sectorName="", streetName="", inactive = ""): StatusResp[seq[SectorProcess]] =
  result.ts = toUnix getTime()
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
    if sectorName != "": "AND sector.name LIKE '%" & sectorName & "%'" else: ""
  let vSearchStreet =
    if streetName != "":
      &", (SELECT count(*) FROM street WHERE sector_id = sector.id AND name LIKE '%{streetName}%') as cnt_str"
      else:
        ""
  let vCnttreet =
    if streetName != "":
      &"AND cnt_str <> 0"
      else:
        ""
  var sqlStr = """SELECT name as sectorName, sector_internal_id, firstname, lastname,
          MAX(date_start), date_finish, user_id,
          sector.id as sector_id, user_sector.id, plz, pfix,
          (SELECT SUM(total_families) FROM street WHERE sector_id = sector.id) as total_families,
          (CASE
            WHEN date_finish IS NULL
              THEN '1'
              ELSE '0'
          END) as flag_d_finish
          {*vSearchStreet*}
          FROM sector
          LEFT JOIN user_sector ON user_sector.sector_id = sector.id {*d_f_c*}
          LEFT JOIN user ON user.id = user_sector.user_id AND user.id *vuId_c* ?
          WHERE
            sector.corpus_id = ?
            {*vInactive*}
            {*v_search_sector*}
            {*vCnttreet*}
            AND sector.id *vsId_c* ?
          GROUP BY sector.id
          ORDER BY flag_d_finish, date_finish ASC, plz, pfix
        """
          .replace("{*vInactive*}", vInactive)
          .replace("*vsId_c*", vsId[0])
          .replace("*vuId_c*", vuId[0])
          .replace("{*d_f_c*}", dFinCond)
          .replace("{*v_search_sector*}", vSearchSect)
          .replace("{*vSearchStreet*}", vSearchStreet)
          .replace("{*vCnttreet*}", vCnttreet)
  if uId != "":
    sqlStr = sqlStr.replace("LEFT", "")
  dbg:
    echo sId, " -- ", sqlStr
  let sectRows = db.getAllRows(
      sqlStr.sql,
        vuId[1], rChck.rowToken[3], vsId[1] )
  #echo "sectRows:", sectRows
  if sectRows.len == 0 or sectRows[0][0] == "":
    return result
  result.status = stOk
  result.resp = newSeqOfCap[SectorProcess](sectRows.len)
  for r in sectRows:
    #if uId == "" and r[5] == "": #in case show all should no show sector if is not returned yet
      #continue
    var sectP = SectorProcess(name: r[0], sector_internal_id: r[1], firstName: r[2], lastName: r[3],
            date_start: r[4], date_finish: r[5],
            user_id: -1, sector_id: r[7].parseInt, id: -1,
            totalFamilies: r[11].parseInt
        )
    #if sectP.firstname != "": #someone took this sector - why if statement here???
    sectP.user_id = r[6].parseInt
    sectP.id = r[8].parseInt
    result.resp.add sectP

proc newSectProcess*(db: DbConn, t, sId, uId, startDate: string): StatusResp[seq[SectorProcess]] =
  result.ts = toUnix getTime()
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
    result.message = "Неудачно: сегодня на руках не может быть больше 4-х участков"
    return result
  let
    fDate = (now() - 2.days).format normalDateFmt
    finPrCntRow = db.getRow(sql"""SELECT count(*) FROM user_sector
      INNER JOIN sector ON user_sector.sector_id = sector.id AND sector.inactive <> 1
      INNER JOIN user ON user.id = user_sector.user_id
      INNER JOIN role ON user.role_id = role.id AND role.role = 'user'
      WHERE user_sector.user_id = ? AND user_sector.date_finish > ?""", vUid, fDate)
  let cntGiveBack = finPrCntRow[0].parseInt
  if cntGiveBack >= 50:
    result.message = "Неудачно: c " & fDate & " сдано много участков: " & $cntGiveBack
    return result
  dbg:
    echo "begin insert process: ", sPrRow
  db.exec(sql"BEGIN")
  db.exec(sql"""UPDATE street
        SET status_street_id = 0
            WHERE sector_id = ?""",
                sId)
  var sqlIns = """INSERT INTO user_sector
          (user_id, sector_id, date_start, time_start)
          VALUES(
            *??*, ?, ?, ?
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
                t, sId, sDate, $now())
  if sPrId == -1 or not db.tryExec(sql"COMMIT"):
    db.exec(sql"ROLLBACK")
    return result
  result = db.getSectProcess(t, sId)


proc delProcess*(db: DbConn, t, pId: string, ifAdmin = false): StatusResp[int] =
  result.ts = toUnix getTime()
  result.status = stUnknown
  var rChck: tuple[isOk: bool, rowToken: Row]
  resultCheckToken(db, t)
  var errMsg: string
  let uId = rChck.rowToken[2]
  db.exec(sql"BEGIN")
  try:
    if ifAdmin:
      db.exec(sql"""DELETE
            FROM user_sector
              WHERE id = ?""", pId)
    else:
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
  result.ts = toUnix getTime()
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
              date_finish = ?,
              time_finish = ?
          WHERE id = ?""",
            vsDate, vfDate, $now(), pId)
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
  result.ts = toUnix getTime()
  result.status = stUnknown
  var rChck: tuple[isOk: bool, rowToken: Row]
  resultCheckToken(db, t)
  let streetRows = db.getAllRows(sql"""SELECT 
          s.id, s.name, s.sector_id, status_street.name, s.geometry, s.total_families, sector.name as sectorName
          FROM street as s
          LEFT JOIN status_street ON status_street.id = s.status_street_id
          INNER JOIN sector ON sector.id = s.sector_id
          WHERE sector_id = ?""", sId)
  #dbg: echo "streetRows:", streetRows
  for s in streetRows:
    let st = if s[3] != "": s[3] else: "strNotStarted"
    result.resp.add SectorStreets(id: s[0].parseInt,
              name: s[1], sector_id: s[2].parseInt, status: parseEnum[StreetStatus](st),
              geometry: s[4], totalFamilies: s[5].parseInt().Natural,
              sectorName: s[6])


proc setStatusStreets*(db: DbConn, t, strsStatus: string): StatusResp[int] =
  result.ts = toUnix getTime()
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

proc getUserList*(db: DbConn, corpus_id: int): StatusResp[seq[User]] = 
  result.ts = toUnix getTime()
  result.status = stUnknown
  let rowUs = db.getAllRows(sql"""SELECT 
                user.*, role.role
                FROM user, role 
                WHERE user.role_id = role.id AND corpus_id = ?""", corpus_id)
  for u in rowUs:
    result.resp.add(row2User(u))
  #result = (isOk: true, user: row2User(rowU))              


proc processed*(db: DbConn, reportFromDate: string): StatusResp[seq[SectorProcessed]] = 
  result.ts = toUnix getTime()
  result.status = stUnknown
  let rows = db.getAllRows(sql"""SELECT user_sector.id, name as sector_name, user.id, firstname, lastname, time_start, time_finish
              FROM sector
              JOIN user_sector ON user_sector.sector_id = sector.id AND user_sector.time_finish is not NULL AND time_start > ? 
              JOIN user ON user.id = user_sector.user_id
              WHERE sector.corpus_id = 1""", reportFromDate)
  for r in rows:
    result.resp.add(row2Processed(r))


proc cntSectors(db: DbConn): int =
  var sqlTxt = """SELECT COUNT(*)
      FROM sector
      WHERE sector.corpus_id = 1 AND sector.inactive = 0"""
  let row = db.getRow(sql sqlTxt)
  row[0].parseInt


proc periodCntProcessed(db: DbConn, dFrom, dTo: string): int =
  var sqlTxt = """SELECT COUNT(*)
          FROM (SELECT 'x'
          FROM user_sector as usrsect
          INNER JOIN sector on sector.id = usrsect.sector_id AND sector.corpus_id = 1 AND sector.inactive = 0
          WHERE date_finish >= ? and date_finish <= ?
          GROUP BY sector_id
          )
      """
  let row = db.getRow(sql sqlTxt, dFrom, dTo)
  row[0].parseInt


proc yearReportTxt*(db: DbConn, dTo: string): string =
  let cntS = db.cntSectors
  let dToDt = parse(dTo, "yyyy-MM-dd")
  let dFromDtY = dToDt - 1.years
  let cntPrcsYear = db.periodCntProcessed(dFromDtY.format("yyyy-MM-dd"), dTo)
  let dFromDtM = dToDt - 6.months
  let cntPrcsHalfYear = db.periodCntProcessed(dFromDtM.format("yyyy-MM-dd"), dTo)
  result = fmt"""
  Всего участков: {cntS}
  Обработано в течении 6 мес. с {dFromDtM.format("dd'.'MM'.'yyyy")}: {cntPrcsHalfYear} участков = {(cntPrcsHalfYear * 100 / cntS):6.3f}%
  Обработано в течении года с {dFromDtY.format("dd'.'MM'.'yyyy")}: {cntPrcsYear} участков = {(cntPrcsYear * 100 / cntS):6.3f}%
  """



#[
SELECT sector_internal_id, sector.name, firstname, lastname, date_start, date_finish
          FROM user_sector as usrsect
          INNER JOIN sector on sector.id = usrsect.sector_id AND sector.corpus_id = 1 AND sector.inactive = 0
          INNER JOIN user on usrsect.user_id = user.id
          WHERE date_finish is null
          ORDER BY date_start, sector_internal_id DESC]#



proc lastProcessed*(db: DbConn): string =
  var sqlTxt = """SELECT sector_internal_id, sector.name, firstname, lastname, date_start, date_finish
          FROM user_sector as usrsect
          INNER JOIN sector on sector.id = usrsect.sector_id AND sector.corpus_id = 1 AND sector.inactive = 0
          INNER JOIN user on usrsect.user_id = user.id
          ORDER BY sector_internal_id, date_start DESC
      """
  let rows = db.getAllRows(sql sqlTxt)
  var
    seqSectorIds = newSeq[string]()
    tblSectrProcess = initTable[string, SectorProcess]()
    sectIdTmp: string
  for r in rows.items():
    let
      arrSctId = r[0].split("-")
      idx = repeat('0', 4 - arrSctId[1].len) & arrSctId[1]
      nSectrId = [arrSctId[0], idx].join("-")
    let sectrPrc = SectorProcess(sector_internal_id: r[0], name: r[1], firstname: r[2], lastname: r[3], date_start: r[4], date_finish: r[5])
    if sectIdTmp != nSectrId:
      sectIdTmp = nSectrId
      seqSectorIds.add sectIdTmp
      tblSectrProcess[sectIdTmp] = sectrPrc
  seqSectorIds = seqSectorIds.deduplicate
  seqSectorIds.sort
  var resp = buildHtml table(border = "1", cellpadding="5", cellspacing="1"):
    tr:
      th:
        text "Участок"
      th:
        text "Возвещатель"
      th:
        text "Взят"
      th:
        text "Обработан"
    for sId in seqSectorIds:
        tr:
          td:
            text tblSectrProcess[sId].name
          td:
            text tblSectrProcess[sId].lastname & " " & tblSectrProcess[sId].firstname
          td:
            text tblSectrProcess[sId].date_start
          td:
            text tblSectrProcess[sId].date_finish
  $resp


proc portfolio*(db: DbConn): string =
  var sqlTxt = """SELECT sector_internal_id, firstname, lastname, date_start, date_finish  
          FROM user_sector as usrsect
          INNER JOIN sector on sector.id = usrsect.sector_id AND sector.corpus_id = 1 AND sector.inactive = 0
          INNER JOIN user on usrsect.user_id = user.id
          ORDER BY date_start
      """
  let rows = db.getAllRows(sql sqlTxt)
  var
    seqSectorIds = newSeq[string]()
    tblSectrProcess = initTable[string, seq[SectorProcess]]()
  for r in rows:
    let
      arrSctId = r[0].split("-")
      idx = repeat('0', 4 - arrSctId[1].len) & arrSctId[1]
      nSectrId = [arrSctId[0], idx].join("-")
      sectrPrc = SectorProcess(sector_internal_id: r[0], firstname: r[1], lastname: r[2], date_start: r[3], date_finish: r[4])
    seqSectorIds.add nSectrId
    discard tblSectrProcess.hasKeyOrPut(nSectrId, newSeq[SectorProcess]())
    tblSectrProcess[nSectrId].add sectrPrc
  seqSectorIds = seqSectorIds.deduplicate
  seqSectorIds.sort

  proc buildSectrTbl(sectorId: string, tblSectrProcess: Table[string, seq[SectorProcess]]): VNode =
    let tFmt = initTimeFormat("dd'.'MM'.'yyyy")
    result = buildHtml table(border = "1", cellpadding="5", cellspacing="1"):
      tr:
        td(colspan = "2", align = "center"):
          strong:
            text tblSectrProcess[sectorId][0].sector_internal_id
      for v in tblSectrProcess[sectorId]:
        let
          dStart = v.date_start.parse("yyyy-MM-dd").format(tFmt)
          dFinish = if v.date_finish != "": v.date_finish.parse("yyyy-MM-dd").format(tFmt) else: ""
        tr:
          td(colspan = "2", align = "center"):
            text fmt"{v.firstname} {v.lastname}"
        tr:
          td:
            text fmt"{dStart}"
          td:
            text fmt"{dFinish}"
  var sectrHtmlTbls: seq[VNode]
  for sectr in seqSectorIds:
    sectrHtmlTbls.add buildSectrTbl(sectr, tblSectrProcess)
  let tblsLen = sectrHtmlTbls.len
  var cntTr = 5
  var idx: int
  let tab = buildHtml html():
    body:
      table:
        while tblsLen > idx:
          #var sHtmTbl = sectrHtmlTbls[idx]
          #if cntTr == 0:
          #cntTr = 5
          tr(valign = "top"):
            while tblsLen > idx and cntTr > 0:
              let sHtmTbl = sectrHtmlTbls[idx]
              td:
                br:
                  discard
                sHtmTbl
              inc idx
              dec cntTr
            cntTr = 5
  ["<!DOCTYPE html>", $tab].join("")