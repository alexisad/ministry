#import ministry
import util/types
import unittest, httpclient, json


suite "user API":
    echo "suite setup: run once before the tests"
    let c = newHttpClient()
    var adminToken, userToken: string
    
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
            
    test "delete user Pavel":
        let statusJsn = c.getContent("http://127.0.0.1:5000/user/delete?email=p.tarasow%40gmail.com&token=" & adminToken).parseJson()
        let status = statusJsn.to(StatusResp).status
        require(status)
    
    test "load data":
        let d = readFile("Büdingen_2019-09-15T16_52_06+02_00.json")
        let letdJsn = cast[MinistryArea](parseJson d)
        require(true)
    echo "suite teardown: run once after the tests"


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