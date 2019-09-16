import tables

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
  TokenResp* = object
    token*: string
  StatusResp* = object
    status*: bool


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
      postalCode, district, city*: string
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
      
  