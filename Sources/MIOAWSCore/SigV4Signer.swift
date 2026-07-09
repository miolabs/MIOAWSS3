//
//  SigV4Signer.swift
//  MIOAWSS3
//
//  AWS Signature Version 4 request signer.
//  https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-authenticating-requests.html
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct SigV4Signer : Sendable
{
    // Hex SHA-256 of an empty body, used for GET/DELETE requests
    public static let emptyBodySHA256 = sha256_hex( Data() )

    public let service : String
    public let region  : String

    public init ( service: String, region: String )
    {
        self.service = service
        self.region  = region
    }

    // MARK: - Signing

    // Signs the request in place: sets Host, x-amz-date, x-amz-content-sha256,
    // x-amz-security-token (when present) and Authorization headers.
    // `bodyHash` is the hex SHA-256 of the request payload — the caller computes it
    // so the body does not need to be attached to the request yet.
    // `amzDate` (yyyyMMdd'T'HHmmss'Z') is injectable for tests; defaults to now.
    public func sign ( request: inout URLRequest, credentials: AWSCredentials, bodyHash: String, amzDate: String? = nil ) throws
    {
        guard let url = request.url, let host = url.host else {
            throw SigV4Error.invalidRequestURL
        }

        let date       = amzDate ?? SigV4Signer.amzDate()
        let short_date = String( date.prefix( 8 ) )

        var host_header = host
        if let port = url.port { host_header += ":\(port)" }

        request.setValue( host_header, forHTTPHeaderField: "Host" )
        request.setValue( date,        forHTTPHeaderField: "x-amz-date" )
        request.setValue( bodyHash,    forHTTPHeaderField: "x-amz-content-sha256" )
        if let token = credentials.sessionToken {
            request.setValue( token, forHTTPHeaderField: "x-amz-security-token" )
        }

        // Only sign headers we set explicitly. Headers URLSession adds on its own
        // (Accept-Encoding, User-Agent, Content-Length...) must stay unsigned or the
        // transmitted value could differ from the signed one.
        var headers: [String:String] = [:]
        for (name, value) in request.allHTTPHeaderFields ?? [:] {
            let lower = name.lowercased()
            if lower == "host" || lower == "content-type" || lower == "content-md5"
            || lower == "range" || lower == "date" || lower.hasPrefix( "x-amz-" ) {
                headers[ lower ] = SigV4Signer.canonicalHeaderValue( value )
            }
        }
        headers[ "host" ] = host_header

        let sorted_names      = headers.keys.sorted()
        let canonical_headers = sorted_names.map { "\($0):\(headers[$0]!)" }.joined( separator: "\n" )
        let signed_headers    = sorted_names.joined( separator: ";" )

        // url.path returns the decoded path, re-encode it the AWS way
        let canonical_uri   = SigV4Signer.uriEncode( url.path.isEmpty ? "/" : url.path, encodeSlash: false )
        let canonical_query = SigV4Signer.canonicalQueryString( url.query )

        var creq = ( request.httpMethod ?? "GET" ) + "\n"
        creq += canonical_uri + "\n"
        creq += canonical_query + "\n"
        creq += canonical_headers + "\n\n"
        creq += signed_headers + "\n"
        creq += bodyHash

        let scope          = "\(short_date)/\(region)/\(service)/aws4_request"
        let string_to_sign = "AWS4-HMAC-SHA256\n\(date)\n\(scope)\n\( sha256_hex( Data( creq.utf8 ) ) )"

        let signing_key = sigv4_signing_key( shortDate: short_date, region: region, service: service, secretKey: credentials.secretKey )
        let signature   = hex_string( hmac_sha256( string_to_sign, key: signing_key ) )

        let auth = "AWS4-HMAC-SHA256 "
                 + "Credential=\(credentials.accessKey)/\(scope),"
                 + "SignedHeaders=\(signed_headers),"
                 + "Signature=\(signature)"

        request.setValue( auth, forHTTPHeaderField: "Authorization" )
    }

    // MARK: - Canonicalization helpers

    // AWS UriEncode: unreserved characters (A-Z a-z 0-9 - . _ ~) stay, everything else
    // is %XX percent-encoded (uppercase hex) over the UTF-8 bytes. '/' is kept as a
    // path separator when encodeSlash is false.
    public static func uriEncode ( _ string: String, encodeSlash: Bool ) -> String
    {
        var out = ""
        for byte in Array( string.utf8 ) {
            switch byte {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"),
                 UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "_"), UInt8(ascii: "~"):
                out.append( Character( UnicodeScalar( byte ) ) )
            case UInt8(ascii: "/") where encodeSlash == false:
                out.append( "/" )
            default:
                out += String( format: "%%%02X", byte )
            }
        }
        return out
    }

    // Sorted, re-encoded query string. Parameters without a value get a trailing '='
    // as the spec requires (e.g. "?lifecycle" -> "lifecycle=").
    static func canonicalQueryString ( _ query: String? ) -> String
    {
        guard let query, query.isEmpty == false else { return "" }

        var params: [(String,String)] = []
        for pair in query.split( separator: "&", omittingEmptySubsequences: true ) {
            let parts = pair.split( separator: "=", maxSplits: 1, omittingEmptySubsequences: false )
            let name  = String( parts[0] ).removingPercentEncoding ?? String( parts[0] )
            let value = parts.count > 1 ? ( String( parts[1] ).removingPercentEncoding ?? String( parts[1] ) ) : ""
            params.append( ( uriEncode( name, encodeSlash: true ), uriEncode( value, encodeSlash: true ) ) )
        }

        params.sort { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }

        return params.map { "\($0.0)=\($0.1)" }.joined( separator: "&" )
    }

    // Trim and collapse sequential inner spaces, per the SigV4 spec
    static func canonicalHeaderValue ( _ value: String ) -> String
    {
        return value.trimmingCharacters( in: .whitespaces )
                    .split( separator: " ", omittingEmptySubsequences: true )
                    .joined( separator: " " )
    }

    public static func amzDate ( _ date: Date = Date() ) -> String
    {
        let df = DateFormatter()
        df.locale     = Locale( identifier: "en_US_POSIX" )
        df.timeZone   = TimeZone( secondsFromGMT: 0 )
        df.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return df.string( from: date )
    }
}

public enum SigV4Error : Error
{
    case invalidRequestURL
}
