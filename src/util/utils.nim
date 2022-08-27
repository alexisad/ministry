import db_sqlite, times, types, random, strutils

proc allPasswordLetters(): string =
    let sl = {'a'..'h', 'j'..'k', 'm'..'n', 'p'..'z', '2'..'9'}
    for i in 1..3:
        for c in sl:
            result &= $c
const
    PasswordLetters* = allPasswordLetters()

template dbg*(x: untyped): untyped =
    when not defined(release):
        x

proc checkToken*(db: DbConn, t: string): tuple[isOk: bool, rowToken: Row] =
    let rowToken = db.getRow(sql"""SELECT 
                token.id, token, token.user_id,
                corpus_id
                FROM 
                token
                INNER JOIN user ON token.user_id = user.id
                WHERE 
                token = ? AND date_activity > ? """, t, $(now() - 60.minutes))
    if rowToken[2] == "":
        result.isOk = false
        return result
    db.exec(sql"""UPDATE token
        SET date_activity = ?
        WHERE token = ?""", $now(), t)
    (isOk: true, rowToken: rowToken)


template resultCheckToken*(db: DbConn, t: string): untyped =
    rChck = checkToken(db, t)
    if not rChck.isOk:
        result.status = stLoggedOut
        return result

template genPassword*(pass: typed, defPass = "", cnt = 5): untyped =
    if defPass != "":
        pass = defPass
    else:
        pass = PasswordLetters
        shuffle(pass)
        pass = pass[0..cnt-1]


proc row2User*(rowU: Row, showPass = false): User =
    result.id = rowU[0].parseInt
    result.corpus_id = rowU[1].parseInt
    result.firstname = rowU[2]
    result.lastname = rowU[3]
    result.email = rowU[4]
    result.active = rowU[7].parseInt
    result.apiKey = rowU[8]
    result.role = rowU[9]
    if showPass:
        result.password = rowU[5]
    result.role_id = rowU[6].parseInt


proc row2Processed*(row: Row): SectorProcessed =
    result.sector_id = row[0].parseInt
    result.name = row[1]
    result.user_id = row[2].parseInt
    result.firstname = row[3]
    result.lastname = row[4]
    result.time_start = row[5]
    result.time_finish = row[6]
