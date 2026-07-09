//
//  S3Wrapper.swift
//  MIOAWSS3
//
//  Thin S3 client on top of URLSession + SigV4. No AWS SDK.
//

import Foundation
import MIOAWSCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum S3ACL : String, Sendable
{
    case `private`              = "private"
    case publicRead             = "public-read"
    case publicReadWrite        = "public-read-write"
    case authenticatedRead      = "authenticated-read"
    case awsExecRead            = "aws-exec-read"
    case bucketOwnerRead        = "bucket-owner-read"
    case bucketOwnerFullControl = "bucket-owner-full-control"
}

public enum S3Error : Error
{
    case invalidURL( String )
    case requestFailed( statusCode: Int, code: String?, message: String? )
    case message( String )
}

extension S3Error : LocalizedError
{
    public var errorDescription: String? {
        switch self {
        case let .invalidURL( url ):
            return "[S3Error] Invalid URL: \(url)"
        case let .requestFailed( status, code, message ):
            return "[S3Error] HTTP \(status) \(code ?? "Unknown code") - \"\(message ?? "Missing message")\""
        case let .message( msg ):
            return "[S3Error] \(msg)"
        }
    }
}

public final class S3Wrapper : @unchecked Sendable
{
    private let region      : String
    private let credentials : AWSCredentials
    private let endpoint    : URL?
    private let signer      : SigV4Signer
    private let session     : URLSession

    // `endpoint` switches to path-style addressing ({endpoint}/{bucket}/{key}) for
    // S3-compatible services (MinIO, Spaces...). Default is AWS virtual-hosted style.
    public init ( region: String, key: String, secret: String, endpoint: URL? = nil )
    {
        self.region      = region
        self.credentials = AWSCredentials( accessKey: key, secretKey: secret )
        self.endpoint    = endpoint
        self.signer      = SigV4Signer( service: "s3", region: region )

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 240
        self.session = URLSession( configuration: config )
    }

    // MARK: - Download

    public func getObject ( path: String, bucket: String ) async throws -> Data?
    {
        let req = try makeRequest( method: "GET", path: path, bucket: bucket, bodyHash: SigV4Signer.emptyBodySHA256 )
        let (data, response) = try await send( req )
        try validate( response, data: data )
        return data
    }

    @available(*, noasync, message: "this method blocks the calling thread, use the async version instead")
    public func getObject ( path: String, bucket: String ) throws -> Data?
    {
        let req = try makeRequest( method: "GET", path: path, bucket: bucket, bodyHash: SigV4Signer.emptyBodySHA256 )
        let (data, response) = try sendSync( req )
        try validate( response, data: data )
        return data
    }

    // MARK: - Upload

    public func putObject ( data: Data, path: String, bucket: String, acl: S3ACL? = nil, mimeType: String? = nil ) async throws
    {
        let req = try makePutRequest( data: data, path: path, bucket: bucket, acl: acl, mimeType: mimeType )
        let (rdata, response) = try await send( req )
        try validate( response, data: rdata )
    }

    @available(*, noasync, message: "this method blocks the calling thread, use the async version instead")
    public func putObject ( data: Data, path: String, bucket: String, acl: S3ACL? = nil, mimeType: String? = nil ) throws
    {
        let req = try makePutRequest( data: data, path: path, bucket: bucket, acl: acl, mimeType: mimeType )
        let (rdata, response) = try sendSync( req )
        try validate( response, data: rdata )
    }

    // MARK: - Deletion

    public func deleteObject ( path: String, bucket: String ) async throws
    {
        let req = try makeRequest( method: "DELETE", path: path, bucket: bucket, bodyHash: SigV4Signer.emptyBodySHA256 )
        let (data, response) = try await send( req )
        try validate( response, data: data )
    }

    @available(*, noasync, message: "this method blocks the calling thread, use the async version instead")
    public func deleteObject ( path: String, bucket: String ) throws
    {
        let req = try makeRequest( method: "DELETE", path: path, bucket: bucket, bodyHash: SigV4Signer.emptyBodySHA256 )
        let (data, response) = try sendSync( req )
        try validate( response, data: data )
    }

    // MARK: - Request building

    func makeRequest ( method: String, path: String, bucket: String, bodyHash: String, headers: [String:String] = [:] ) throws -> URLRequest
    {
        let key         = path.hasPrefix( "/" ) ? String( path.dropFirst() ) : path
        let encoded_key = SigV4Signer.uriEncode( key, encodeSlash: false )

        let url_string: String
        if let endpoint = endpoint {
            var base = endpoint.absoluteString
            if base.hasSuffix( "/" ) { base = String( base.dropLast() ) }
            url_string = "\(base)/\(bucket)/\(encoded_key)"
        }
        else {
            url_string = "https://\(bucket).s3.\(region).amazonaws.com/\(encoded_key)"
        }

        guard let url = URL( string: url_string ) else {
            throw S3Error.invalidURL( url_string )
        }

        var req = URLRequest( url: url )
        req.httpMethod = method
        for (h, v) in headers {
            req.setValue( v, forHTTPHeaderField: h )
        }

        try signer.sign( request: &req, credentials: credentials, bodyHash: bodyHash )

        return req
    }

    func makePutRequest ( data: Data, path: String, bucket: String, acl: S3ACL?, mimeType: String? ) throws -> URLRequest
    {
        var headers = [ "Content-Type": mimeType ?? "application/octet-stream" ]
        if let acl = acl {
            // signed x-amz-acl header on the PUT itself, no separate PutObjectAcl call
            headers[ "x-amz-acl" ] = acl.rawValue
        }

        var req = try makeRequest( method: "PUT", path: path, bucket: bucket, bodyHash: sha256_hex( data ), headers: headers )
        req.httpBody = data
        return req
    }

    // MARK: - Transport

    private func send ( _ request: URLRequest ) async throws -> (Data, HTTPURLResponse)
    {
        return try await withCheckedThrowingContinuation { continuation in
            self.session.dataTask( with: request ) { data, response, error in
                if let error = error {
                    continuation.resume( throwing: error )
                }
                else if let http = response as? HTTPURLResponse {
                    continuation.resume( returning: (data ?? Data(), http) )
                }
                else {
                    continuation.resume( throwing: S3Error.message( "Invalid response type" ) )
                }
            }.resume()
        }
    }

    // Blocks only the calling thread: URLSession runs the request on its own queue,
    // no Swift concurrency involved, so the cooperative pool is never starved.
    private func sendSync ( _ request: URLRequest ) throws -> (Data, HTTPURLResponse)
    {
        let semaphore = DispatchSemaphore( value: 0 )
        var result: Result<(Data, HTTPURLResponse), Error> = .failure( S3Error.message( "Request did not complete" ) )

        session.dataTask( with: request ) { data, response, error in
            if let error = error {
                result = .failure( error )
            }
            else if let http = response as? HTTPURLResponse {
                result = .success( (data ?? Data(), http) )
            }
            else {
                result = .failure( S3Error.message( "Invalid response type" ) )
            }
            semaphore.signal()
        }.resume()

        semaphore.wait()

        return try result.get()
    }

    // MARK: - Response handling

    private func validate ( _ response: HTTPURLResponse, data: Data ) throws
    {
        guard (200...299).contains( response.statusCode ) else {
            let (code, message) = S3Wrapper.parseXMLError( data )
            throw S3Error.requestFailed( statusCode: response.statusCode, code: code, message: message )
        }
    }

    static func parseXMLError ( _ data: Data ) -> (String?, String?)
    {
        guard let xml = String( data: data, encoding: .utf8 ) else { return (nil, nil) }

        func tag ( _ name: String ) -> String? {
            guard let open  = xml.range( of: "<\(name)>" ),
                  let close = xml.range( of: "</\(name)>", range: open.upperBound..<xml.endIndex )
            else { return nil }
            return String( xml[ open.upperBound..<close.lowerBound ] )
        }

        return ( tag( "Code" ), tag( "Message" ) )
    }
}
