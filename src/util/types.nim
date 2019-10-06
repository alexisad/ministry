import tables, strutils, db_sqlite, times

type
  User* = object
    id*: int
    corpus_id*: int
    firstname*: string
    lastname*: string
    email*: string
    role_id*: int
    role*: string
    password*: string
    active*: int
    token*: string
  TokenResp* = object
    token*: string
  StatusResp*[T] = object
    status*: bool
    resp*: T
  SectorProcess* = object
    name*: string
    sector_internal_id*: string
    firstname*, lastname*: string
    date_start*, date_finish*: string
    id*, user_id*, sector_id*: int
  CSectorProcess* = object
    name*: cstring
    sector_internal_id*: cstring
    firstname*, lastname*: cstring
    date_start*, date_finish*: cstring
    id*, user_id*, sector_id*: int


type
  Latitude* = range[-90.00..90.00]
  Longitude* = range[-180.00..180.00]
  Altitude* = range[-20_000.00..200_000.00]
  Coord* = ref object
      lat*: Latitude
      lng*: Longitude
  Link* = ref object
      linkId*: int
      name*: string
      cityId*: int
      districtId*: int
      postalCode*: string
      neighborLinks*: seq[int]
      geometry*: seq[Coord]
      readOnly*: bool
      addedToMap*: bool
      addedToSector*: bool
  Street* = ref object
      name*: string
      links*: seq[Link]
      sector*: Sector
  Sector* = ref object
      postalCode*, district*, city*: string
      pFix*: int
      streets*: OrderedTable[string, seq[Link]]
      shownOnMap*: bool
      exclude*: bool
  MinistryArea* = ref object
      name*: string
      cities*: OrderedTable[string, MinistryCity]
  MinistryCity* = ref object
      allLinks*: tables.Table[int, Link]
      allStreets*: tables.OrderedTable[string, Street]
      cachedTiles*: tables.Table[string, ref object]
      allSectors*: OrderedTable[string, Sector]
      lastPostfix*: tables.Table[string, int]
      

proc startDate*(s: SectorProcess): DateTime =
  s.date_start.parse(initTimeFormat("yyyy-MM-dd"))


proc finishDate*(s: SectorProcess): DateTime =
  s.date_finish.parse(initTimeFormat("yyyy-MM-dd"))


proc name*(s: Sector): string =
    @[s.postalCode & "-" & $s.pFix, s.city, s.district].join(" ").strip

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


