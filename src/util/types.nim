import tables, strutils, #[db_sqlite,]# times

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
    apiKey*: string
  TokenResp* = object
    token*: string
  StatusType* = enum
    stOk = "OK", stUnknown = "unknown", stLoggedOut = "loggedOut"
  #CStatusType* {.pure.} = enum
    #stOk = "OK", stUnknown = "unknown", stLoggedOut = "loggedOut"
  StreetStatus* = enum
    strNotStarted = "strNotStarted", strStarted = "strStarted", strFinished = "strFinished"
  StatusResp*[T] = object
    status*: StatusType
    message*: string
    resp*: T
    ts*: int64
  SectorProcess* = object
    name*: string
    sector_internal_id*: string
    firstname*, lastname*: string
    date_start*, date_finish*: string
    id*, user_id*, sector_id*: int
    totalFamilies*: int
  SectorProcessed* = object
    name*: string
    firstname*, lastname*: string
    time_start*, time_finish*: string
    user_id*, sector_id*: int
  SectorStreets* = object
    id*, sector_id*: int
    name*: string
    geometry*: string
    totalFamilies*: Natural
    sectorName*: string
    status*: StreetStatus

type
    Point* = object
        x*: float
        y*: float

type
  Latitude* = range[-90.00..90.00]
  Longitude* = range[-180.00..180.00]
  Altitude* = range[-20_000.00..200_000.00]
  Coord* = ref object
      lat*: Latitude
      lng*: Longitude
  AdmSector* = ref object
    name*: string
    streets*: seq[AdminStreet]
  AreaSectors* = ref object
    sectorsInAdminNames*: TableRef[string, seq[string]]
    sectors*: OrderedTableRef[string, AdmSector]
  City* = ref object
    id*: string
    name*: string
    pdeName*: seq[PdeName]
  District* = ref object
    id*: string
    name*: string
    pdeName*: seq[PdeName]
    polygonOuter*: seq[float]
    outerPoints*: seq[Point]
  AdminStreet* = ref object
    city*: City
    postalCode*: string
    district*: District
    street*: string
    isStrNameEmpty*: bool
    roadlinks*: seq[RoadLink]
  RoadLink* = ref object
    linkId*: string
    name*: seq[PdeName]
    isStrNameEmpty*: bool
    districtId*: string
    cityId*: string
    coords*: seq[Point]
    refNodeCoord*: Point
    nonRefNodeCoord*: Point
    linkLen*: float
    refLinks*: seq[string]
    nonRefLinks*: seq[string]
    postalCode*: string
    addresses*: seq[string]
    urban*: string
  PdeNameType* = enum
    abbreviation = "A - abbreviation", baseName = "B - base name",
    exonym = "E - exonym", shortenedName = "K - shortened name",
    synonym = "S - synonym", unknown = "unknown"
  PdeNameKind* = enum
    name, translit, phoneme
  PdeName* = ref object
    name*: string
    lang*: LangCode
    nameType*: PdeNameType
    nameKind*: PdeNameKind
  LangCode* = distinct string
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
      totalFamilies: Natural
  Sector* = ref object
      postalCode*, district*, folkDistrict*, city*: string
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

type
  Locations* = object
    items*: seq[Location]
  Location* = object
    address*: Address
  Address* = object
    street*, houseNumber*: string

proc startDate*(s: SectorProcess): DateTime =
  s.date_start.parse(initTimeFormat("yyyy-MM-dd"))


proc finishDate*(s: SectorProcess): DateTime =
  s.date_finish.parse(initTimeFormat("yyyy-MM-dd"))

#[
  proc startDate*(s: SectorProcess): DateTime =
  (s.date_start).parse(initTimeFormat("yyyy-MM-dd"))


proc finishDate*(s: SectorProcess): DateTime =
  (s.date_finish).parse(initTimeFormat("yyyy-MM-dd"))
]#



proc name*(s: Sector): string =
    @[s.postalCode & "-" & $s.pFix,
          s.city, if s.folkDistrict != "": s.folkDistrict else: s.district].join(" ").strip



