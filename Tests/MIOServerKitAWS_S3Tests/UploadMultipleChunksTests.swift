//
//  UploadTests.swift
//
//
//  Created by Javier Segura Perez on 13/6/24.
//

import XCTest
@testable import MIOServerKitAWS_S3

//
// Example with the same information from AWS: https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-streaming.html#example-signature-calculations-streaming
//

let AWS_ACCESS_KEY = "AKIAIOSFODNN7EXAMPLE"
let AWS_SECRET_ACCESS_KEY = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
let AWS_BUCKET_NAME = "examplebucket"
let AWS_REGION = "us-east-1"
let AWS_HOST = "s3.amazonaws.com"

let EXAMPLE_FILE_DATE = "20130524T000000Z"
let EXAMPLE_FILE_NAME = "chunkObject.txt"
let EXAMPLE_FILE_CONTENT = Data( repeating: 97, count: 65 * 1024 )
let EXAMPLE_TOTAL_BODY_LENGTH = 66824 // data + metadata of all chunk bodies
let EXAMPLE_FILE_CHUNK_DATA_LEN = 64 * 1024

let EXAMPLE_FILE_CHUNK_BODY_DATA_LEN_0 = (64 * 1024) + 90 // 64K in hex: 10000
let EXAMPLE_FILE_CHUNK_BODY_DATA_LEN_1 = (1 * 1024) + 88  // 1K in hex: 400
let EXAMPLE_FILE_CHUNK_BODY_DATA_LEN_2 = (0 * 1024) + 86

let S3Credentials = Credentials(key: AWS_ACCESS_KEY, secret: AWS_SECRET_ACCESS_KEY )

extension Data
{
    func offset(offset:Int = 0, length:Int) -> Data {
        let start = offset
        let end = ( offset + length ) < self.count ? ( offset + length ) : self.count
        return self[ start..<( end ) ]
    }
}

extension MIOServerKitAWS_S3Tests
{
    func generateMultipleChunkSignatureV4Request() -> SignatureV4.SignatureRequest
    {
        return SignatureV4.SignatureRequest( .put,
                                             AWS_HOST,
                                             "/\(AWS_BUCKET_NAME)/\(EXAMPLE_FILE_NAME)",
                                             options: [
                                                .date( EXAMPLE_FILE_DATE ),
                                                .storageClassReducedRedundancy,
                                                .decodedContentLength(EXAMPLE_FILE_CONTENT.count),
                                                .contentLength(EXAMPLE_TOTAL_BODY_LENGTH),
                                                .contentEncoding( .chunked ),
                                                .contentSHA256(.multipleChunk)
                                             ],
                                             body: EXAMPLE_FILE_CONTENT
        )
    }
    
    func testMultipleChunckSignatureSeedHeaders()
    {
        let headers = generateMultipleChunkSignatureV4Request().headers
        
        let check_headers: [String:String] = [
            "x-amz-date": EXAMPLE_FILE_DATE,
            "x-amz-storage-class": "REDUCED_REDUNDANCY",
            "x-amz-content-sha256": AWS_SIGNATURE_PAYLOAD_TYPE.multipleChunk.rawValue,
            "x-amz-decoded-content-length": "\(EXAMPLE_FILE_CONTENT.count)",
            "Content-Length": "\(EXAMPLE_TOTAL_BODY_LENGTH)", // file content with metadata fo all chunks
            "Content-Encoding": "aws-chunked",
            "Host": AWS_HOST
        ]
        for (h,v) in check_headers {
            XCTAssertTrue( v == headers[h] )
        }
    }
    
    func testMultipleChunkAuthorizationHeader()
    {
        let r = generateMultipleChunkSignatureV4Request()

        let signer = S3SignatureV4( AWS_REGION )
        let ctx = signer.createContext( from: r, dateString: EXAMPLE_FILE_DATE, credentials: S3Credentials, payloadType: .multipleChunk )
        
        let sign = signer.generateSignature(context: ctx )
        
        let auth = signer.generateAuthorizationHeader( signature: sign, context: ctx )
        
        XCTAssertTrue( auth == "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request,SignedHeaders=content-encoding;content-length;host;x-amz-content-sha256;x-amz-date;x-amz-decoded-content-length;x-amz-storage-class,Signature=4f232c4386841ef735655705268965c44a0e4690baa4adea153f7db9fa80a0a9")
        
    }
    
    func generateSeedSignature() -> String
    {
        let r = generateMultipleChunkSignatureV4Request()
        
        let signer = S3SignatureV4( AWS_REGION )
        let ctx = signer.createContext( from: r, dateString: EXAMPLE_FILE_DATE, credentials: S3Credentials, payloadType: .multipleChunk )
        
        return signer.generateSignature( context: ctx )
    }
    
    func testMultipleChunkUploadSeedSignature()
    {
        let sign = generateSeedSignature()
        
        XCTAssertTrue( sign == "4f232c4386841ef735655705268965c44a0e4690baa4adea153f7db9fa80a0a9" )
    }
    
    func generateChunkBodyInfo1() -> (S3SignatureV4, SigContext, Data)
    {
        let r = generateMultipleChunkSignatureV4Request()
        
        let signer = S3SignatureV4( AWS_REGION )
        let ctx = signer.createContext( from: r, dateString: EXAMPLE_FILE_DATE, credentials: S3Credentials, payloadType: .multipleChunk )

        let sub_data = EXAMPLE_FILE_CONTENT.offset( length: 64 * 1024 )
                        
        return (signer, ctx, sub_data)
    }
    
    func testGenerateMultipleChunkBodyString1()
    {
        let (signer,ctx,sub_data) = generateChunkBodyInfo1()
        
        let seed = generateSeedSignature()
        
        let body_str = signer.generateChunkBodyString( previousSignature: seed, data: sub_data, context: ctx )
        
        let check_body = """
        AWS4-HMAC-SHA256-PAYLOAD
        20130524T000000Z
        20130524/us-east-1/s3/aws4_request
        4f232c4386841ef735655705268965c44a0e4690baa4adea153f7db9fa80a0a9
        e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        bf718b6f653bebc184e1479f1935b8da974d701b893afcf49e701f3e2f9f9c5a
        """
        
         XCTAssertTrue( body_str == check_body )
    }
    
    func testMultipleChunkBodyStringSignature1()
    {
        let (signer,ctx,sub_data) = generateChunkBodyInfo1()
        
        let seed = generateSeedSignature()
        let body_str = signer.generateChunkBodyString( previousSignature: seed, data: sub_data, context: ctx )
        
        let signature = signer.generateChunkBodySignature( bodyString: body_str, context: ctx )
        
         XCTAssertTrue( signature == "ad80c730a21e5b8d04586a2213dd63b9a0e99e0e2307b0ade35a65485a288648" )
    }
    
    func testMultipleChunkBody1()
    {
        let (signer,ctx,sub_data) = generateChunkBodyInfo1()
        
        let seed = generateSeedSignature()
        let body_str = signer.generateChunkBodyString( previousSignature: seed, data: sub_data, context: ctx )
        let signature = signer.generateChunkBodySignature( bodyString: body_str, context: ctx )
        
        let (meta, body) = signer.generateChunkBody( data: sub_data, signature: signature, context: ctx )
        
        XCTAssertTrue( meta == "10000;chunk-signature=ad80c730a21e5b8d04586a2213dd63b9a0e99e0e2307b0ade35a65485a288648\r\n" )
        
        XCTAssertTrue( body == meta.data(using: .utf8)! + sub_data + "\r\n".data(using: .utf8)! )
    }
    
    func generateChunkBodyInfo2() -> (S3SignatureV4, SigContext, Data)
    {
        let r = generateMultipleChunkSignatureV4Request()
        
        let signer = S3SignatureV4( AWS_REGION )
        let ctx = signer.createContext( from: r, dateString: EXAMPLE_FILE_DATE, credentials: S3Credentials, payloadType: .multipleChunk )
        
        let sub_data = EXAMPLE_FILE_CONTENT.offset( offset: 64 * 1024, length: 64 * 1024 )
        
        return (signer, ctx, sub_data)
    }
    
    func testGenerateMultipleChunkBodyString2()
    {
        let (signer1,ctx1,sub_data1) = generateChunkBodyInfo1()
        let seed = generateSeedSignature()
        let body_str1 = signer1.generateChunkBodyString( previousSignature: seed, data: sub_data1, context: ctx1 )
        let signature = signer1.generateChunkBodySignature( bodyString: body_str1, context: ctx1 )

        
        let (signer,ctx,sub_data) = generateChunkBodyInfo2()
        
        let body_str = signer.generateChunkBodyString( previousSignature: signature, data: sub_data, context: ctx )
        
        let check_body = """
        AWS4-HMAC-SHA256-PAYLOAD
        20130524T000000Z
        20130524/us-east-1/s3/aws4_request
        ad80c730a21e5b8d04586a2213dd63b9a0e99e0e2307b0ade35a65485a288648
        e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        2edc986847e209b4016e141a6dc8716d3207350f416969382d431539bf292e4a
        """
        
        XCTAssertTrue( body_str == check_body )
    }
    
    func testMultipleChunkBodyStringSignature2()
    {
        let (signer1,ctx1,sub_data1) = generateChunkBodyInfo1()
        let seed = generateSeedSignature()
        let body_str1 = signer1.generateChunkBodyString( previousSignature: seed, data: sub_data1, context: ctx1 )
        let signature1 = signer1.generateChunkBodySignature( bodyString: body_str1, context: ctx1 )
        
        let (signer,ctx,sub_data) = generateChunkBodyInfo2()
        
        let body_str = signer.generateChunkBodyString( previousSignature: signature1, data: sub_data, context: ctx )
        let signature = signer.generateChunkBodySignature( bodyString: body_str, context: ctx )
        
        XCTAssertTrue( signature == "0055627c9e194cb4542bae2aa5492e3c1575bbb81b612b7d234b86a503ef5497" )
    }
    
    func testMultipleChunkBody2()
    {
        let (signer1,ctx1,sub_data1) = generateChunkBodyInfo1()
        let seed = generateSeedSignature()
        let body_str1 = signer1.generateChunkBodyString( previousSignature: seed, data: sub_data1, context: ctx1 )
        let signature1 = signer1.generateChunkBodySignature( bodyString: body_str1, context: ctx1 )
        
        let (signer,ctx,sub_data) = generateChunkBodyInfo2()
        
        let body_str = signer.generateChunkBodyString( previousSignature: signature1, data: sub_data, context: ctx )
        let signature = signer.generateChunkBodySignature( bodyString: body_str, context: ctx )
        let (meta, body) = signer.generateChunkBody( data: sub_data, signature: signature, context: ctx )
        
        XCTAssertTrue( meta == "400;chunk-signature=0055627c9e194cb4542bae2aa5492e3c1575bbb81b612b7d234b86a503ef5497\r\n" )
        
        XCTAssertTrue( body == meta.data(using: .utf8)! + sub_data + "\r\n".data(using: .utf8)! )
    }
    
    func generateChunkBodyInfo3() -> (S3SignatureV4, SigContext, Data)
    {
        let r = generateMultipleChunkSignatureV4Request()
        
        let signer = S3SignatureV4( AWS_REGION )
        let ctx = signer.createContext( from: r, dateString: EXAMPLE_FILE_DATE, credentials: S3Credentials, payloadType: .multipleChunk )
        
        return (signer, ctx, Data() )
    }
    
    func testGenerateMultipleChunkBodyString3()
    {
        let (signer1,ctx1,sub_data1) = generateChunkBodyInfo1()
        let seed = generateSeedSignature()
        let body_str1 = signer1.generateChunkBodyString( previousSignature: seed, data: sub_data1, context: ctx1 )
        let signature1 = signer1.generateChunkBodySignature( bodyString: body_str1, context: ctx1 )

        let (signer2,ctx2,sub_data2) = generateChunkBodyInfo2()
        let body_str2 = signer2.generateChunkBodyString( previousSignature: signature1, data: sub_data2, context: ctx2 )
        let signature2 = signer2.generateChunkBodySignature( bodyString: body_str2, context: ctx2 )

        let (signer,ctx,sub_data) = generateChunkBodyInfo3()
        let body_str = signer.generateChunkBodyString( previousSignature: signature2, data: sub_data, context: ctx )

        let check_body = """
        AWS4-HMAC-SHA256-PAYLOAD
        20130524T000000Z
        20130524/us-east-1/s3/aws4_request
        0055627c9e194cb4542bae2aa5492e3c1575bbb81b612b7d234b86a503ef5497
        e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        """
        
        XCTAssertTrue( body_str == check_body )
    }
    
    func testMultipleChunkBodyStringSignature3()
    {
        let (signer1,ctx1,sub_data1) = generateChunkBodyInfo1()
        let seed = generateSeedSignature()
        let body_str1 = signer1.generateChunkBodyString( previousSignature: seed, data: sub_data1, context: ctx1 )
        let signature1 = signer1.generateChunkBodySignature( bodyString: body_str1, context: ctx1 )

        let (signer2,ctx2,sub_data2) = generateChunkBodyInfo2()
        let body_str2 = signer2.generateChunkBodyString( previousSignature: signature1, data: sub_data2, context: ctx2 )
        let signature2 = signer2.generateChunkBodySignature( bodyString: body_str2, context: ctx2 )

        let (signer,ctx,sub_data) = generateChunkBodyInfo3()
        let body_str = signer.generateChunkBodyString( previousSignature: signature2, data: sub_data, context: ctx )

        let signature = signer.generateChunkBodySignature( bodyString: body_str, context: ctx )
        
        XCTAssertTrue( signature == "b6c6ea8a5354eaf15b3cb7646744f4275b71ea724fed81ceb9323e279d449df9" )
    }
    
    func testMultipleChunkBody3()
    {
        let (signer1,ctx1,sub_data1) = generateChunkBodyInfo1()
        let seed = generateSeedSignature()
        let body_str1 = signer1.generateChunkBodyString( previousSignature: seed, data: sub_data1, context: ctx1 )
        let signature1 = signer1.generateChunkBodySignature( bodyString: body_str1, context: ctx1 )

        let (signer2,ctx2,sub_data2) = generateChunkBodyInfo2()
        let body_str2 = signer2.generateChunkBodyString( previousSignature: signature1, data: sub_data2, context: ctx2 )
        let signature2 = signer2.generateChunkBodySignature( bodyString: body_str2, context: ctx2 )

        let (signer,ctx,sub_data) = generateChunkBodyInfo3()
        let body_str = signer.generateChunkBodyString( previousSignature: signature2, data: sub_data, context: ctx )
        let signature = signer.generateChunkBodySignature( bodyString: body_str, context: ctx )
        
        let (meta, body) = signer.generateChunkBody( data: sub_data, signature: signature, context: ctx )
        
        XCTAssertTrue( meta == "0;chunk-signature=b6c6ea8a5354eaf15b3cb7646744f4275b71ea724fed81ceb9323e279d449df9\r\n" )
        
        XCTAssertTrue( body == meta.data(using: .utf8)! + sub_data + "\r\n".data(using: .utf8)! )
    }
    
    func testUploadChunk() throws 
    {
        let s3 = S3(apn: "", accountID: "", region: AWS_REGION, credentials: Credentials(key: AWS_ACCESS_KEY, secret: AWS_SECRET_ACCESS_KEY))
        
        let requests = try s3.putFileMultipleChunkRequests( AWS_HOST, "/\(AWS_BUCKET_NAME)/\(EXAMPLE_FILE_NAME)", EXAMPLE_FILE_CONTENT, contentDateString: EXAMPLE_FILE_DATE, sizeLimit: EXAMPLE_FILE_CHUNK_DATA_LEN )
             
        XCTAssertTrue( requests.count == 3 )

        // Check request 0
        
        let req0_headers = requests[0].allHTTPHeaderFields!
        let req0_body = requests[0].httpBody!

        let check_headers_0: [String:String] = [
            "x-amz-date": EXAMPLE_FILE_DATE,
            "x-amz-storage-class": "REDUCED_REDUNDANCY",
            "x-amz-content-sha256": AWS_SIGNATURE_PAYLOAD_TYPE.multipleChunk.rawValue,
            "x-amz-decoded-content-length": "\(EXAMPLE_FILE_CONTENT.count)",
            "Content-Length": "\(EXAMPLE_FILE_CHUNK_BODY_DATA_LEN_0)", // file content with metadata
            "Content-Encoding": "aws-chunked",
            "Host": AWS_HOST
        ]
        for (h,v) in check_headers_0 {
            let value = req0_headers[h]
            XCTAssertTrue(value != nil, "Header \(h) found nil value")
            XCTAssertTrue( v == value, "Header \(h) expected value: \(v) but found \(value!)" )
        }
        
        let body_data_0 = EXAMPLE_FILE_CONTENT.offset( length: 64 * 1024 )
        let body_meta_0 = "10000;chunk-signature=ad80c730a21e5b8d04586a2213dd63b9a0e99e0e2307b0ade35a65485a288648\r\n"
        let body_0 = body_meta_0.data(using: .utf8)! + body_data_0 + "\r\n".data(using: .utf8)!
        XCTAssertTrue( req0_body == body_0 )

        let auth_header_0 = requests[0].value(forHTTPHeaderField: "Authorization")
        XCTAssertTrue( auth_header_0 == "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request,SignedHeaders=content-encoding;content-length;host;x-amz-content-sha256;x-amz-date;x-amz-decoded-content-length;x-amz-storage-class,Signature=4f232c4386841ef735655705268965c44a0e4690baa4adea153f7db9fa80a0a9")
        
        // Check request 1
        
        let req1_headers = requests[1].allHTTPHeaderFields!
        let req1_body = requests[1].httpBody!

        let check_headers1: [String:String] = [
            "x-amz-date": EXAMPLE_FILE_DATE,
            "x-amz-storage-class": "REDUCED_REDUNDANCY",
            "x-amz-content-sha256": AWS_SIGNATURE_PAYLOAD_TYPE.multipleChunk.rawValue,
            "x-amz-decoded-content-length": "\(EXAMPLE_FILE_CONTENT.count)",
            "Content-Length": "\(EXAMPLE_FILE_CHUNK_BODY_DATA_LEN_1)", // file content with metadata
            "Content-Encoding": "aws-chunked",
            "Host": AWS_HOST
        ]
        for (h,v) in check_headers1 {
            let value = req1_headers[h]
            XCTAssertTrue(value != nil, "Header \(h) found nil value")
            XCTAssertTrue( v == value, "Header \(h) expected value: \(v) but found \(value!)" )
        }
        
        let body_data_1 = EXAMPLE_FILE_CONTENT.offset( offset: 64 * 1024, length: 64 * 1024 )
        let body_meta_1 = "400;chunk-signature=0055627c9e194cb4542bae2aa5492e3c1575bbb81b612b7d234b86a503ef5497\r\n"
        let body_1 = body_meta_1.data(using: .utf8)! + body_data_1 + "\r\n".data(using: .utf8)!
        XCTAssertTrue( req1_body == body_1 )
        
        let auth_header_1 = requests[1].value(forHTTPHeaderField: "Authorization")
        XCTAssertTrue( auth_header_1 == "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request,SignedHeaders=content-encoding;content-length;host;x-amz-content-sha256;x-amz-date;x-amz-decoded-content-length;x-amz-storage-class,Signature=4f232c4386841ef735655705268965c44a0e4690baa4adea153f7db9fa80a0a9")
        
        // Check request 2
        
        let req2_headers = requests[2].allHTTPHeaderFields!
        let req2_body = requests[2].httpBody!

        let check_headers2: [String:String] = [
            "x-amz-date": EXAMPLE_FILE_DATE,
            "x-amz-storage-class": "REDUCED_REDUNDANCY",
            "x-amz-content-sha256": AWS_SIGNATURE_PAYLOAD_TYPE.multipleChunk.rawValue,
            "x-amz-decoded-content-length": "\(EXAMPLE_FILE_CONTENT.count)",
            "Content-Length": "\(EXAMPLE_FILE_CHUNK_BODY_DATA_LEN_2)", // file content with metadata
            "Content-Encoding": "aws-chunked",
            "Host": AWS_HOST
        ]
        for (h,v) in check_headers2 {
            let value = req2_headers[h]
            XCTAssertTrue(value != nil, "Header \(h) found nil value")
            XCTAssertTrue( v == value, "Header \(h) expected value: \(v) but found \(value!)" )
        }
        
        let body_data_2 = Data()
        let body_meta_2 = "0;chunk-signature=b6c6ea8a5354eaf15b3cb7646744f4275b71ea724fed81ceb9323e279d449df9\r\n"
        let body_2 = body_meta_2.data(using: .utf8)! + body_data_2 + "\r\n".data(using: .utf8)!
        XCTAssertTrue( req2_body == body_2 )
        
        let auth_header_2 = requests[2].value(forHTTPHeaderField: "Authorization")
        XCTAssertTrue( auth_header_2 == "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request,SignedHeaders=content-encoding;content-length;host;x-amz-content-sha256;x-amz-date;x-amz-decoded-content-length;x-amz-storage-class,Signature=4f232c4386841ef735655705268965c44a0e4690baa4adea153f7db9fa80a0a9")

    }
}
