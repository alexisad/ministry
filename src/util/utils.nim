import db_sqlite, times, types



proc checkToken*(db: DbConn, t: string): tuple[isOk: bool, rowToken: Row] =
    let rowToken = db.getRow(sql"""SELECT 
                token.id, token, token.user_id,
                corpus_id
                FROM 
                token
                INNER JOIN user ON token.user_id = user.id
                WHERE 
                token = ? AND date_activity > ? """, t, $(now() - 10.minutes))
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