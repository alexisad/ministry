#import ministry
import util/[types, utils]
import unittest, httpclient, json, times, uri


suite "user API":
    echo "suite setup: run once before the tests"
    let c = newHttpClient()
    var adminToken, userToken, sectPrId: string
    let normalDateFmt = initTimeFormat("yyyy-MM-dd")
    var sectorsPr: StatusResp[seq[SectorProcess]]
    
    when false:
        setup:
            echo "run before each test"
            
        teardown:
            echo "run after each test"
    
    test "check login":
        # give up and stop if this fails
        let tokenJsn = c.postContent("http://127.0.0.1:5000?email=sadovoyalexander%40yahoo.de&pass=111&test=1").parseJson()
        adminToken = tokenJsn.to(TokenResp).token
        echo "admin user login token: ", adminToken
        check(adminToken != "")
    
    test "get user":
        let respUsrJsn = c.getContent("http://127.0.0.1:5000/user/get?email=sadovoyalexander%40yahoo.de&token=" & adminToken).parseJson()
        let user = respUsrJsn.to(StatusResp[User]).resp
        check(user.email == "sadovoyalexander@yahoo.de")

    test "empty user by corrupted token":
        let respUsrJsn = c.getContent("http://127.0.0.1:5000/user/get?email=sadovoyalexander%40yahoo.de&token=5rt4h58").parseJson()
        let user = respUsrJsn.to(StatusResp[User]).resp
        check(user.email == "")

    test "new user if doesn't exist":
        let respUsrJsn = c.getContent("http://127.0.0.1:5000/user/get?email=p.tarasow%40gmail.com&token=" & adminToken).parseJson()
        var user = respUsrJsn.to(StatusResp[User]).resp
        if user.email != "p.tarasow@gmail.com":
            let respUsrJsn = c.getContent("http://127.0.0.1:5000/user/new?firstname=Pavel&lastname=Tarasow&email=p.tarasow%40gmail.com&role=user&password=222&token=" & adminToken).parseJson()
            user = respUsrJsn.to(StatusResp[User]).resp
        check(user.email == "p.tarasow@gmail.com")
    
    test "new user":
        let respUsrJsn = c.getContent("http://127.0.0.1:5000/user/new?firstname=Michael&lastname=Sadovoy&email=michi.sadik%40gmail.com&role=user&password=333&token=" & adminToken).parseJson()
        let user = respUsrJsn.to(StatusResp[User]).resp
        check(user.email == "michi.sadik@gmail.com")

    test "check login for Pavel":
        # give up and stop if this fails
        let tokenJsn = c.postContent("http://127.0.0.1:5000?email=p.tarasow%40gmail.com&pass=222&test=1").parseJson()
        userToken = tokenJsn.to(TokenResp).token
        echo "user login token: ", userToken
        check(userToken != "")

    test "except delete user Pavel by role user":
        expect(HttpRequestError):
            let statusJsn = c.getContent("http://127.0.0.1:5000/user/delete?email=p.tarasow%40gmail.com&token=" & userToken).parseJson()
                
    
    test "upload data":
        let statusJsn = c.getContent("http://127.0.0.1:5000/sector/upload?token=" & adminToken).parseJson()
        let status = statusJsn.to(StatusResp[int]).status
        check(status == stOk)

    test "get all sectors in process":
        let statusJsn = c.getContent("http://127.0.0.1:5000/sector/process?token=" & adminToken).parseJson()
        let statusJsnU = c.getContent("http://127.0.0.1:5000/sector/process?token=" & userToken).parseJson()
        sectorsPr = statusJsn.to(StatusResp[seq[SectorProcess]])
        let sectorsPrU = statusJsnU.to(StatusResp[seq[SectorProcess]])
        echo "sectorsPr:: ", sectorsPr.resp.len, " ", sectorsPrU.resp.len
        #sectPrId = $(sectorsPr[5].sector_id)
        check(sectorsPr.resp.len != 0 and sectorsPrU.resp.len != 0)

    test "add new process":
        let statusJsn = c.getContent("http://127.0.0.1:5000/sector/process/new?" &
                                "token=" & adminToken &
                                "&sectorId=" & $(sectorsPr.resp[5].sector_id) &
                                "&startDate=" & encodeUrl( (now() - 10.days).format normalDateFmt )
                        ).parseJson()
        let r = statusJsn.to(StatusResp[seq[SectorProcess]])
        let status = r.status
        sectPrId = $r.resp[r.resp.high].id
        check(status == stOk)

    test "add new process":
        let respUsrJsn = c.getContent("http://127.0.0.1:5000/user/get?email=p.tarasow%40gmail.com&token=" & adminToken).parseJson()
        var user = respUsrJsn.to(StatusResp[User]).resp
        let statusJsn = c.getContent("http://127.0.0.1:5000/sector/process/new?" &
                                "token=" & adminToken &
                                "&sectorId=" & $sectorsPr.resp[6].sector_id &
                                "&userId=" & $user.id &
                                "&startDate=" & encodeUrl( (now() - 10.days).format normalDateFmt )
                        ).parseJson()
        let status = statusJsn.to(StatusResp[seq[SectorProcess]]).status
        check(status == stOk)

    test "get all sectors in process":
        let statusJsn = c.getContent("http://127.0.0.1:5000/sector/process?" &
                                        "token=" & adminToken &
                                        "&sectorId=" & $sectorsPr.resp[5].sector_id
                            ).parseJson()
        let statusJsnU = c.getContent("http://127.0.0.1:5000/sector/process?token=" & userToken).parseJson()
        let sectorsPrById = statusJsn.to(StatusResp[seq[SectorProcess]])
        echo "sectorsPrById: ", sectorsPrById
        let sectorsPrU = statusJsnU.to(StatusResp[seq[SectorProcess]])
        #sectPrId = $(sectorsPr[5].sector_id)
        check(sectorsPrById.resp.len != 0 and sectorsPrU.resp.len != 0)

    test "update process: set finish date":
        let statusJsn = c.getContent("http://127.0.0.1:5000/sector/process/update?" &
                                "token=" & adminToken &
                                "&processId=" & sectPrId &
                                "&finishDate=" & encodeUrl( (now() - 5.days).format normalDateFmt )
                        ).parseJson()
        let status = statusJsn.to(StatusResp[seq[SectorProcess]]).status
        check(status == stOk)

    test "update process: not allow set finish date if it < start":
        let statusJsn = c.getContent("http://127.0.0.1:5000/sector/process/update?" &
                                "token=" & adminToken &
                                "&processId=" & sectPrId &
                                "&finishDate=" & encodeUrl( (now() - 11.days).format normalDateFmt )
                        ).parseJson()
        let status = statusJsn.to(StatusResp[seq[SectorProcess]]).status
        check(status != stOk)

    test "add new process for the same sector because prev. is finished":
        let statusJsn = c.getContent("http://127.0.0.1:5000/sector/process/new?" &
                                "token=" & adminToken &
                                "&sectorId=" & $sectorsPr.resp[5].sector_id &
                                "&startDate=" & encodeUrl( (now() - 3.days).format normalDateFmt )
                        ).parseJson()
        let status = statusJsn.to(StatusResp[seq[SectorProcess]]).status
        check(status == stOk)


    test "shouldn't add the same sector to process if not finished yet":
        let statusJsn = c.getContent("http://127.0.0.1:5000/sector/process/new?" &
                                "token=" & userToken &
                                "&sectorId=" & sectPrId
                        ).parseJson()
        let status = statusJsn.to(StatusResp[seq[SectorProcess]]).status
        check(status != stOk)
    
    test "impossible delete user Pavel, he has processes":
        let statusJsn = c.getContent("http://127.0.0.1:5000/user/delete?email=p.tarasow%40gmail.com&token=" & adminToken).parseJson()
        let status = statusJsn.to(StatusResp[int]).status
        check(status != stOk)

    test "delete user Michael":
        let statusJsn = c.getContent("http://127.0.0.1:5000/user/delete?email=michi.sadik%40gmail.com&token=" & adminToken).parseJson()
        let status = statusJsn.to(StatusResp[int]).status
        check(status == stOk)

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