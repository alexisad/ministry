import db_sqlite, times, types, random

const
    PasswordLetters = {'A'..'H', 'J'..'N', 'P'..'Z', 'a'..'h', 'j'..'n', 'p'..'z', '2'..'9'}

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

proc genPassword*(cnt = 5): string =
    #randomize()
    result = $PasswordLetters
    shuffle(result)
    result = result[0..cnt-1]