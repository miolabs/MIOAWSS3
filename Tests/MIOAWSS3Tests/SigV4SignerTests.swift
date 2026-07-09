//
//  SigV4SignerTests.swift
//  MIOAWSS3
//
//  Offline tests against the official AWS Signature V4 examples:
//  https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-header-based-auth.html
//  Access key AKIAIOSFODNN7EXAMPLE, bucket examplebucket, region us-east-1,
//  date 20130524T000000Z — expected signatures are published by AWS.
//

import XCTest
@testable import MIOAWSCore
@testable import MIOAWSS3

final class SigV4SignerTests: XCTestCase
{
    let credentials = AWSCredentials( accessKey: "AKIAIOSFODNN7EXAMPLE",
                                      secretKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY" )
    let signer  = SigV4Signer( service: "s3", region: "us-east-1" )
    let amzDate = "20130524T000000Z"

    func signatureOf ( _ request: URLRequest ) -> String? {
        guard let auth = request.value( forHTTPHeaderField: "Authorization" ),
              let range = auth.range( of: "Signature=" ) else { return nil }
        return String( auth[ range.upperBound... ] )
    }

    // Example: GET Object (with Range header)
    func testGetObjectSignature ( ) throws
    {
        var req = URLRequest( url: URL( string: "https://examplebucket.s3.amazonaws.com/test.txt" )! )
        req.httpMethod = "GET"
        req.setValue( "bytes=0-9", forHTTPHeaderField: "Range" )

        try signer.sign( request: &req, credentials: credentials, bodyHash: SigV4Signer.emptyBodySHA256, amzDate: amzDate )

        XCTAssertEqual( signatureOf( req ), "f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41" )
    }

    // Example: PUT Object — covers '$' encoding in the key, Date and storage-class headers
    func testPutObjectSignature ( ) throws
    {
        let body = Data( "Welcome to Amazon S3.".utf8 )
        XCTAssertEqual( sha256_hex( body ), "44ce7dd67c959e0d3524ffac1771dfbba87d2b6b4b4e99e42034a8b803f8b072" )

        var req = URLRequest( url: URL( string: "https://examplebucket.s3.amazonaws.com/test%24file.text" )! )
        req.httpMethod = "PUT"
        req.setValue( "Fri, 24 May 2013 00:00:00 GMT", forHTTPHeaderField: "Date" )
        req.setValue( "REDUCED_REDUNDANCY", forHTTPHeaderField: "x-amz-storage-class" )

        try signer.sign( request: &req, credentials: credentials, bodyHash: sha256_hex( body ), amzDate: amzDate )

        XCTAssertEqual( signatureOf( req ), "98ad721746da40c64f1a55b78f14c238d841ea1380cd77a1b5971af0ece108bd" )
    }

    // Example: GET Bucket Lifecycle — query parameter without value ("?lifecycle" -> "lifecycle=")
    func testGetBucketLifecycleSignature ( ) throws
    {
        var req = URLRequest( url: URL( string: "https://examplebucket.s3.amazonaws.com/?lifecycle" )! )
        req.httpMethod = "GET"

        try signer.sign( request: &req, credentials: credentials, bodyHash: SigV4Signer.emptyBodySHA256, amzDate: amzDate )

        XCTAssertEqual( signatureOf( req ), "fea454ca298b7da1c68078a5d1bdbfbbe0d65c699e0f91ac7a200a0136783543" )
    }

    // Example: List Objects — multiple query parameters, sorted canonical query
    func testListObjectsSignature ( ) throws
    {
        var req = URLRequest( url: URL( string: "https://examplebucket.s3.amazonaws.com/?max-keys=2&prefix=J" )! )
        req.httpMethod = "GET"

        try signer.sign( request: &req, credentials: credentials, bodyHash: SigV4Signer.emptyBodySHA256, amzDate: amzDate )

        XCTAssertEqual( signatureOf( req ), "34b48302e7b5fa45bde8084f4b7868a86f0a534bc59db6670ed5711ef69dc6f7" )
    }

    // MARK: - Encoding

    func testUriEncoding ( )
    {
        XCTAssertEqual( SigV4Signer.uriEncode( "photos/my file.jpg", encodeSlash: false ), "photos/my%20file.jpg" )
        XCTAssertEqual( SigV4Signer.uriEncode( "a+b=c&d.txt",        encodeSlash: false ), "a%2Bb%3Dc%26d.txt" )
        XCTAssertEqual( SigV4Signer.uriEncode( "año/café.png",       encodeSlash: false ), "a%C3%B1o/caf%C3%A9.png" )
        XCTAssertEqual( SigV4Signer.uriEncode( "path/sub",           encodeSlash: true  ), "path%2Fsub" )
        XCTAssertEqual( SigV4Signer.uriEncode( "unreserved-._~09AZaz", encodeSlash: false ), "unreserved-._~09AZaz" )
    }

    func testCanonicalQueryString ( )
    {
        XCTAssertEqual( SigV4Signer.canonicalQueryString( nil ), "" )
        XCTAssertEqual( SigV4Signer.canonicalQueryString( "lifecycle" ), "lifecycle=" )
        XCTAssertEqual( SigV4Signer.canonicalQueryString( "prefix=J&max-keys=2" ), "max-keys=2&prefix=J" )
    }

    // MARK: - Wrapper request building

    func testWrapperBuildsVirtualHostedURL ( ) throws
    {
        let s3  = S3Wrapper( region: "eu-west-1", key: "AKIAIOSFODNN7EXAMPLE", secret: "secret" )
        let req = try s3.makeRequest( method: "GET", path: "/folder/my file.png", bucket: "my-bucket", bodyHash: SigV4Signer.emptyBodySHA256 )

        XCTAssertEqual( req.url?.absoluteString, "https://my-bucket.s3.eu-west-1.amazonaws.com/folder/my%20file.png" )
        XCTAssertNotNil( req.value( forHTTPHeaderField: "Authorization" ) )
        XCTAssertNotNil( req.value( forHTTPHeaderField: "x-amz-date" ) )
        XCTAssertEqual( req.value( forHTTPHeaderField: "x-amz-content-sha256" ), SigV4Signer.emptyBodySHA256 )
    }

    func testWrapperBuildsPathStyleURLForCustomEndpoint ( ) throws
    {
        let s3  = S3Wrapper( region: "us-east-1", key: "k", secret: "s", endpoint: URL( string: "http://localhost:9000" ) )
        let req = try s3.makeRequest( method: "GET", path: "file.txt", bucket: "my-bucket", bodyHash: SigV4Signer.emptyBodySHA256 )

        XCTAssertEqual( req.url?.absoluteString, "http://localhost:9000/my-bucket/file.txt" )
        XCTAssertEqual( req.value( forHTTPHeaderField: "Host" ), "localhost:9000" )
    }

    func testPutRequestCarriesACLAndContentType ( ) throws
    {
        let s3  = S3Wrapper( region: "us-east-1", key: "k", secret: "s" )
        let req = try s3.makePutRequest( data: Data( "hi".utf8 ), path: "a.txt", bucket: "b", acl: .publicRead, mimeType: "text/plain" )

        XCTAssertEqual( req.value( forHTTPHeaderField: "x-amz-acl" ), "public-read" )
        XCTAssertEqual( req.value( forHTTPHeaderField: "Content-Type" ), "text/plain" )
        XCTAssertEqual( req.httpBody, Data( "hi".utf8 ) )

        // both must be signed
        let auth = req.value( forHTTPHeaderField: "Authorization" )!
        XCTAssertTrue( auth.contains( "x-amz-acl" ) )
        XCTAssertTrue( auth.contains( "content-type" ) )
    }

    func testParseXMLError ( )
    {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Error><Code>NoSuchKey</Code><Message>The specified key does not exist.</Message><Key>x.txt</Key></Error>
        """
        let (code, message) = S3Wrapper.parseXMLError( Data( xml.utf8 ) )
        XCTAssertEqual( code, "NoSuchKey" )
        XCTAssertEqual( message, "The specified key does not exist." )
    }
}
