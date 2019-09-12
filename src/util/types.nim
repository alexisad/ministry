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