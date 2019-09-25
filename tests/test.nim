#import ministry
import util/types
import unittest, httpclient, json, times, uri


suite "user API":
    echo "suite setup: run once before the tests"
    let c = newHttpClient()
    var adminToken, userToken, sectPrId: string
    let normalDateFmt = initTimeFormat("yyyy-MM-dd")
    var sectorsPr: seq[SectorProcess]
    
    when false:
        setup:
            echo "run before each test"
            
        teardown:
            echo "run after each test"
    
    test "check login":
        # give up and stop if this fails
        let tokenJsn = c.getContent("http://127.0.0.1:5000/login?email=sadovoyalexander%40yahoo.de&pass=111").parseJson()
        adminToken = tokenJsn.to(TokenResp).token
        echo "admin user login token: ", adminToken
        require(adminToken != "")
    
    test "get user":
        let usrJsn = c.getContent("http://127.0.0.1:5000/user/get?email=sadovoyalexander%40yahoo.de&token=" & adminToken).parseJson()
        let user = usrJsn.to(User)
        require(user.email == "sadovoyalexander@yahoo.de")

    test "HttpRequestError by corrupted token":
        expect(HttpRequestError):
            discard c.getContent("http://127.0.0.1:5000/user/get?email=sadovoyalexander%40yahoo.de&token=5rt4h58").parseJson()

    test "new user":
        let usrJsn = c.getContent("http://127.0.0.1:5000/user/new?firstname=Pavel&lastname=Tarasow&email=p.tarasow%40gmail.com&role=user&password=222&token=" & adminToken).parseJson()
        let user = usrJsn.to(User)
        require(user.email == "p.tarasow@gmail.com")
    
    test "check login for Pavel":
        # give up and stop if this fails
        let tokenJsn = c.getContent("http://127.0.0.1:5000/login?email=p.tarasow%40gmail.com&pass=222").parseJson()
        userToken = tokenJsn.to(TokenResp).token
        echo "user login token: ", userToken
        require(userToken != "")

    test "except delete user Pavel by role user":
        expect(HttpRequestError):
            let statusJsn = c.getContent("http://127.0.0.1:5000/user/delete?email=p.tarasow%40gmail.com&token=" & userToken).parseJson()
                
    
    test "load data":
        let statusJsn = c.getContent("http://127.0.0.1:5000/sector/upload?token=" & adminToken).parseJson()
        let status = statusJsn.to(StatusResp).status
        require(status)

    test "get all sectors in process":
        let statusJsn = c.getContent("http://127.0.0.1:5000/sector/process?token=" & adminToken).parseJson()
        let statusJsnU = c.getContent("http://127.0.0.1:5000/sector/process?token=" & userToken).parseJson()
        sectorsPr = statusJsn.to(seq[SectorProcess])
        let sectorsPrU = statusJsnU.to(seq[SectorProcess])
        sectPrId = $(sectorsPr[5].sector_id)
        require(sectorsPr.len != 0 and sectorsPrU.len != 0)

    test "add new process":
        let statusJsn = c.getContent("http://127.0.0.1:5000/sector/process/new?" &
                                "token=" & adminToken &
                                "&sectorId=" & sectPrId &
                                "&startDate=" & encodeUrl( (now() - 10.days).format normalDateFmt )
                        ).parseJson()
        let status = statusJsn.to(StatusResp).status
        require(status)

    test "add new process":
        let statusJsn = c.getContent("http://127.0.0.1:5000/sector/process/new?" &
                                "token=" & adminToken &
                                "&sectorId=" & $sectorsPr[6].sector_id &
                                "&userId=" & $2 &
                                "&startDate=" & encodeUrl( (now() - 10.days).format normalDateFmt )
                        ).parseJson()
        let status = statusJsn.to(StatusResp).status
        require(status)

    test "update process: set finish date":
        let statusJsn = c.getContent("http://127.0.0.1:5000/sector/process/update?" &
                                "token=" & adminToken &
                                "&processId=" & $sectorsPr[6].id &
                                "&endDate=" & encodeUrl( (now() - 5.days).format normalDateFmt )
                        ).parseJson()
        let status = statusJsn.to(StatusResp).status
        require(status)


    test "shouldn't add the same sector to process":
        let statusJsn = c.getContent("http://127.0.0.1:5000/sector/process/new?" &
                                "token=" & userToken &
                                "&sectorId=" & sectPrId
                        ).parseJson()
        let status = statusJsn.to(StatusResp).status
        require(status == false)
    
    when true:
        test "delete user Pavel":
            let statusJsn = c.getContent("http://127.0.0.1:5000/user/delete?email=p.tarasow%40gmail.com&token=" & adminToken).parseJson()
            let status = statusJsn.to(StatusResp).status
            require(status)

    echo "suite teardown: run once after the tests..."


when false:
    suite "user API":
        setup:
            #let c = newHttpClient()
            #let r = c.getContent("http://127.0.0.1:5000/login?user=sadovoyalexander%40yahoo.de&pass=111")
            echo "admin user login token: "#, r
        teardown:
            echo "run after each test"
        
            test "essential truths":
                # give up and stop if this fails
                require(false)
            
        when true:
            test "slightly less obvious stuff":
                # print a nasty message and move on, skipping
                # the remainder of this block
                check(1 != 1)
                check("asd"[2] == 'd')
            
            test "out of bounds error is thrown on bad access":
                let v = @[1, 2, 3]  # you can do initialization here
                expect(IndexError):
                    discard v[4]
            
            echo "suite teardown: run once after the tests"