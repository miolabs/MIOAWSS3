//
//  SignatureV4.swift
//  
//
//  Created by David Trallero on 03/09/2020.
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif


public enum AWS_SIGNATURE_PAYLOAD_TYPE: String
{
    case UNSIGNED_PAYLOAD = "UNSIGNED-PAYLOAD"
    case SINGLE_CHUNK = "AWS4-HMAC-SHA256"
    case MULTIPLE_CHUNK = "STREAMING-AWS4-HMAC-SHA256-PAYLOAD"
}

let AMZ_CONTENT_SHA256_HEADER = "x-amz-content-sha256"


public struct SigContext
{
    public let creq   : String
    public let headers: String
}

/**
 * Signature Version 4
 * @link http://docs.aws.amazon.com/general/latest/gr/signature-version-4.html
 */
public class SignatureV4
{
    // const ISO8601_BASIC = "Ymd\THis\Z";
    var service   : String
    var region    : String
    var isUnsigned: Bool

    /**
     * @param string service Service name to use when signing
     * @param string region  Region name to use when signing
     * @param bool isUnsigned Flag to make request have unsigned payload.
     *        Unsigned body is used primarily for streaming requests.
     */
    public init ( service: String, region: String, isUnsigned: Bool = false )
    {
        self.service    = service
        self.region     = region
        self.isUnsigned = isUnsigned
    }


    /**
     * The following headers are not signed because signing these headers
     * would potentially cause a signature mismatch when sending a request
     * through a proxy or if modified at the HTTP client level.
     *
     * @return array
     */
    public static func getHeaderBlacklist ( ) -> Set<String>
    {
        return Set( [ "cache-control"
                    //, "content-type"
//                    , "content-length"
                    , "expect"
                    , "max-forwards"
                    , "pragma"
                    , "range"
                    , "te"
                    , "if-match"
                    , "if-none-match"
                    , "if-modified-since"
                    , "if-unmodified-since"
                    , "if-range"
                    , "accept"
                    , "authorization"
                    , "proxy-authorization"
                    , "from"
                    , "referer"
                    , "user-agent"
                    , "x-amzn-trace-id"
                    , "aws-sdk-invocation-id"
                    , "aws-sdk-retry"
                    ] )
    }


    @discardableResult
    public func signRequest ( _ request: inout URLRequest, _ credentials: Credentials, payloadType: AWS_SIGNATURE_PAYLOAD_TYPE = .SINGLE_CHUNK ) -> String {
        let ldt = gmdate() // 20200905T085054Z
        let sdt = String( ldt[ ldt.startIndex ... ldt.index( ldt.startIndex, offsetBy: 7 ) ] ) // 20200905

        request.setValue(ldt, forHTTPHeaderField: "x-amz-date" )
        //request.setValue( nil, forHTTPHeaderField: "Date" )
        //request.setValue( nil, forHTTPHeaderField: "Authorization" )

        if let token = credentials.getSecurityToken() {
            request.setValue( token, forHTTPHeaderField: "x-amz-security-token" )
        }
        
        let payload    = getPayload( request )
        request.setValue( payload, forHTTPHeaderField: AMZ_CONTENT_SHA256_HEADER )
                
        let cs         = createScope( sdt, region, service )
        let context    = createContext( request, payload )
        let toSign     = createStringToSign( ldt, cs, context.creq )
        let signingKey = getSigningKey( sdt, region, service, credentials.getSecretKey() )
        let signature  = sha256_hmac( toSign, key: signingKey ).map{ String(format: "%02x", $0) }.joined()

//        if payload == AWS_SIGNATURE_TYPE.UNSIGNED_PAYLOAD.rawValue {
//            request.setValue( payload, forHTTPHeaderField: AMZ_CONTENT_SHA256_HEADER )
//        }

        let auth = "AWS4-HMAC-SHA256 "
                 + "Credential=\(credentials.getAccessKeyId())/\(cs), "
                 + "SignedHeaders=\(context.headers), "
                 + "Signature=\(signature)"
        
        request.setValue( auth, forHTTPHeaderField: "Authorization" )
        
        return signature
    }

    /**
     * @param array  parsedRequest
     * @param string payload Hash of the request payload
     * @return array Returns an array of context information
     */
    private func createContext ( _ request: URLRequest, _ payload: String ) -> SigContext
    {
        let blacklist           = SignatureV4.getHeaderBlacklist()
        let allowed_headers     = ( request.allHTTPHeaderFields ?? [:] )
                                    .filter{ (h,v) in !blacklist.contains( h.lowercased() ) }
        let sortedKeys          = Array(allowed_headers.keys).sorted(by: <)
        let canonHeaders        = sortedKeys.map{ h in "\(h.lowercased()):\(allowed_headers[ h ]!)" }.joined( separator: "\n" )
        let signedHeadersString = sortedKeys.map{ $0.lowercased() }.joined( separator: ";" )
        
        var canon = ""
        canon += request.httpMethod! + "\n"
        canon += createCanonicalizedPath( request.url?.path ?? "" ) + "\n"
//      canon += + getCanonicalizedQuery( request.url.query ) + "\n"
        canon += ( request.url?.query ?? "" ) + "\n"
        canon += canonHeaders + "\n\n"
        canon += signedHeadersString + "\n"
        canon += payload
       
        return SigContext( creq: canon, headers: signedHeadersString )
    }
        

    func createCanonicalizedPath ( _ path: String ) -> String
    {
        return (path.count > 0 && path.first! == "/") ? path : "/" + path
    }


    // Returns the arguments sorted alphabetically
    private func getCanonicalizedQuery ( _ query: [ String: Any ] ) -> String
    {
        if query.isEmpty {
            return ""
        }
        
        let sorted_keys = query.keys.sorted()
          , skip_args = Set( ["x-amz-signature"] )
        
        var ret: [ String ] = []

        for key in sorted_keys {
            if skip_args.contains( key ) { continue }
            
            ret.append( getCanonicalQueryArg( key, query[ key ]! ) )
        }
        
        return ret.joined( separator: "&" )
    }
    
    
    public func getCanonicalQueryArg ( _ key: String, _ value: Any ) -> String {
        
//        if value is Array {
//            let arr = value as! Array
//
//            arr.sorted( )
//
//            return arr.map{ v in "\(key)=\(v)" }.joined( separator: "&" )
//        }
        
        return "\(key)=\(value)"
    }


    
    func createStringToSign ( _ longDate: String, _ credentialScope: String, _ creq: String ) -> String
    {
        let hash = sha256_hash( creq.data(using: .utf8)! )

        return "AWS4-HMAC-SHA256\n\(longDate)\n\(credentialScope)\n\(hash)"
    }

    
    /**
     * Get the headers that were used to pre-sign the request.
     * Used for the X-Amz-SignedHeaders header.
     *
     * @param array headers
     * @return array
     */
//    private func getPresignHeaders(array headers)
//    {
//        presignHeaders = [];
//        blacklist = this->getHeaderBlacklist();
//        foreach (headers as name => value) {
//            lName = strtolower(name);
//            if (!isset(blacklist[lName])
//                && name !== self::AMZ_CONTENT_SHA256_HEADER
//            ) {
//                presignHeaders[] = lName;
//            }
//        }
//        return presignHeaders;
//    }
//
//    public func presign(
//        RequestInterface request,
//        CredentialsInterface credentials,
//        expires,
//        array options = []
//    ) {
//
//        startTimestamp = isset(options["start_time"])
//                            ? this->convertToTimestamp(options["start_time"], null)
//                            : time();
//
//        expiresTimestamp = this->convertToTimestamp(expires, startTimestamp);
//
//        parsed = this->createPresignedRequest(request, credentials);
//        payload = this->getPresignedPayload(request);
//        httpDate = gmdate(self::ISO8601_BASIC, startTimestamp);
//        shortDate = substr(httpDate, 0, 8);
//        scope = this->createScope(shortDate, this->region, this->service);
//        credential = credentials->getAccessKeyId() . "/" . scope;
//        if (credentials->getSecurityToken()) {
//            unset(parsed["headers"]["X-Amz-Security-Token"]);
//        }
//        parsed["query"]["X-Amz-Algorithm"] = "AWS4-HMAC-SHA256";
//        parsed["query"]["X-Amz-Credential"] = credential;
//        parsed["query"]["X-Amz-Date"] = gmdate("Ymd\THis\Z", startTimestamp);
//        parsed["query"]["X-Amz-SignedHeaders"] = implode(";", this->getPresignHeaders(parsed["headers"]));
//        parsed["query"]["X-Amz-Expires"] = this->convertExpires(expiresTimestamp, startTimestamp);
//        context = this->createContext(parsed, payload);
//        stringToSign = this->createStringToSign(httpDate, scope, context["creq"]);
//        key = this->getSigningKey(
//            shortDate,
//            this->region,
//            this->service,
//            credentials->getSecretKey()
//        );
//        parsed["query"]["X-Amz-Signature"] = hash_hmac("sha256", stringToSign, key);
//
//        return this->buildRequest(parsed);
//    }


    public func getPayload ( _ request: URLRequest ) -> String
    {
        if isUnsigned && request.url!.scheme!.lowercased() == "https" {
            return AWS_SIGNATURE_PAYLOAD_TYPE.UNSIGNED_PAYLOAD.rawValue
        }
        
        // Calculate the request signature payload
        if let header_sha = request.value(forHTTPHeaderField: AMZ_CONTENT_SHA256_HEADER ) {
            // Handle streaming operations (e.g. Glacier.UploadArchive)
            return header_sha
        }

        return sha256_hash( request.httpBody ?? Data() )
    }

//    protected func getPresignedPayload(RequestInterface request)
//    {
//        return this->getPayload(request);
//    }


//    private func createPresignedRequest(
//        RequestInterface request,
//        CredentialsInterface credentials
//    ) {
//        parsedRequest = this->parseRequest(request);
//
//        // Make sure to handle temporary credentials
//        if (token = credentials->getSecurityToken()) {
//            parsedRequest["headers"]["X-Amz-Security-Token"] = [token];
//        }
//
//        return this->moveHeadersToQuery(parsedRequest);
//    }
//
//
//
//    private func convertToTimestamp(dateValue, relativeTimeBase = null)
//    {
//        if (dateValue instanceof \DateTimeInterface) {
//            timestamp = dateValue->getTimestamp();
//        } elseif (!is_numeric(dateValue)) {
//            timestamp = strtotime(dateValue,
//                                   relativeTimeBase === null ? time() : relativeTimeBase
//            );
//        } else {
//            timestamp = dateValue;
//        }
//
//        return timestamp;
//    }
//
//    private func convertExpires(expiresTimestamp, startTimestamp)
//    {
//        duration = expiresTimestamp - startTimestamp;
//
//        // Ensure that the duration of the signature is not longer than a week
//        if (duration > 604800) {
//            throw new \InvalidArgumentException("The expiration date of a "
//                . "signature version 4 presigned URL must be less than one "
//                . "week");
//        }
//
//        return duration;
//    }
//
//    private func moveHeadersToQuery(array parsedRequest)
//    {
//        foreach (parsedRequest["headers"] as name => header) {
//            lname = strtolower(name);
//            if (substr(lname, 0, 5) == "x-amz") {
//                parsedRequest["query"][name] = header;
//            }
//            blacklist = this->getHeaderBlacklist();
//            if (isset(blacklist[lname])
//                || lname === strtolower(self::AMZ_CONTENT_SHA256_HEADER)
//            ) {
//                unset(parsedRequest["headers"][name]);
//            }
//        }
//
//        return parsedRequest;
//    }
//
//    private func parseRequest(RequestInterface request)
//    {
//        // Clean up any previously set headers.
//        /** @var RequestInterface request */
//        request = request
//            ->withoutHeader("X-Amz-Date")
//            ->withoutHeader("Date")
//            ->withoutHeader("Authorization");
//        uri = request->getUri();
//
//        return [
//            "method"  => request->getMethod(),
//            "path"    => uri->getPath(),
//            "query"   => Psr7\parse_query(uri->getQuery()),
//            "uri"     => uri,
//            "headers" => request->getHeaders(),
//            "body"    => request->getBody(),
//            "version" => request->getProtocolVersion()
//        ];
//    }
//
//    private func buildRequest(array req)
//    {
//        if (req["query"]) {
//            req["uri"] = req["uri"]->withQuery(Psr7\build_query(req["query"]));
//        }
//
//        return new Psr7\Request(
//            req["method"],
//            req["uri"],
//            req["headers"],
//            req["body"],
//            req["version"]
//        );
//    }
}
