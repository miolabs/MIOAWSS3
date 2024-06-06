//
//  s3.swift
//  MIOServerKitAWS_S3
//
//  Created by David Trallero on 05/09/2020.
//

import Foundation
import MIOCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum AWSError: Error
{
    case error(_ code: String, _ message: String, functionName: String = #function)
}


extension AWSError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .error(code, msg, functionName):
            return "[DLDBError] \(functionName) \(code) - \"\(msg)\"."
        }
    }
}

public final class S3 : NSObject
{
    var apn: String // access point name
    var accountID: String
    var region: String
    var credentials: Credentials
    
    public init ( apn: String, accountID: String, region: String, credentials: Credentials ) {
        self.apn         = apn
        self.accountID   = accountID
        self.region      = region
        self.credentials = credentials
    }

    // MARK: - Request
    
    enum FileRequestType : String 
    {
        case get = "GET"
        case put = "PUT"
        case delete = "DELETE"
    }
    
    func fileRequest( _ type:FileRequestType, _ host: String, _ path: String ) -> URLRequest
    {
        print("S3 \(type.rawValue): \(host) \(path)")
        return URLRequest(method: type.rawValue, urlString: api_url( path ) )
    }
    
    // MARK: - Sync methods
    
    public func getFile ( _ host: String, _ path: String ) throws -> Data?
    {
        var req = fileRequest( .get, host, path )
        s3_exec_request( &req, host )
        return try MIOCoreURLDataRequest_sync( req )
        //return try exec_request( &req, host )
    }
    
    public func putFile ( _ host: String, _ path: String, _ content: Data ) throws
    {
        var req = fileRequest( .put, host, path )
        req.httpBody = content
        try exec_request( &req, host )
    }
    
    public func deleteFile ( _ host: String, _ path: String ) throws
    {
        var req = fileRequest( .delete, host, path )
        try exec_request( &req, host )
    }
}

extension S3
{
    func api_url ( _ path: String ) -> String {
        return "https://" + apn + "-" + accountID + ".s3-accesspoint." + region + ".amazonaws.com" + path
    }
    
    func s3_exec_request( _ req: inout URLRequest, _ host: String ) {
        let signature = S3SignatureV4( region )
        req.setValue( host, forHTTPHeaderField: "Host" )
        signature.signRequest( &req, credentials )
    }
    
    @discardableResult
    func exec_request ( _ req: inout URLRequest, _ host: String ) throws -> Data?
    {
        s3_exec_request( &req, host )
        return try dispatch_response( try MIOCoreURLDataRequest_sync( req ) )
    }
        
    func dispatch_response ( _ response: Data? ) throws -> Data?
    {
        if response == nil || response!.isEmpty { return nil }

        let xmlDict = try XMLSerialization.xmlObject( with: response!, options: [] ) as! [String:Any]
        print( "S3: Response \(xmlDict)" )
        if xmlDict[ "__XML_TAG_NAME__" ] as? String == "Error" {
            throw AWSError.error( xmlDict[ "Code"    ] as? String ?? "Unkown CODE"
                                , xmlDict[ "Message" ] as? String ?? "Missing Message" )
        }
        
        return nil
    }
}

// MARK: - Async methods

public typealias S3ProgressCallback = (Float) -> Void
public typealias S3UploadCompletionCallback = (Data?, Error?) -> Void
public typealias S3DownloadCompletionCallback = (_ localPath : URL?, Error?) -> Void

extension S3 : URLSessionTaskDelegate
{
    static var progress_blocks:[ String: S3ProgressCallback? ] = [:]
    
    //  Probado con:
    //  searchPath = .documentDirectory y localSubfolder ="folder"  -> deja el fichero en Documents/folder con el nombre que tuviera en remoto
    //  searchPath = .itemReplacementDirectory y localSubfolder = nil  -> No va en VisionOS
    public func getFile ( _ host: String, _ remotePath: String, _ saveFileURL: URL,  progress: S3ProgressCallback?, completion: @escaping S3DownloadCompletionCallback ) {
        var req = fileRequest( .get, host, remotePath )
        s3_exec_request( &req, host )
        
        S3.progress_blocks[ req.url!.absoluteString ] = progress
        
        let config = URLSessionConfiguration.ephemeral

        let session = URLSession( configuration: config, delegate: self, delegateQueue: .main )
        
        let downloadTask = session.downloadTask( with: req ) { urlOrNil, responseOrNil, errorOrNil in
            
            if let error = errorOrNil {
                print (" S3::getFile error: \(error)")
                completion( nil, error)
                S3.progress_blocks.removeValue( forKey: req.url!.absoluteString )
                return
            }
            
            guard let responseHttp = responseOrNil as? HTTPURLResponse,
                (200...299).contains(responseHttp.statusCode) else {
                print("S3::getFile error responseHttp null or http error code received")
                if let responseHttp = responseOrNil as? HTTPURLResponse{
                    completion( nil, HTTP_S3_StatusCode(rawValue: responseHttp.statusCode))
                }
                else {
                    completion( nil, HTTP_S3_StatusCode.urlSessionUnexpectedError)
                }
                S3.progress_blocks.removeValue( forKey: req.url!.absoluteString )
                return
            }
            
            guard let fileURL = urlOrNil else {
                print("S3::getFile error fileURL null ")
                completion( nil, HTTP_S3_StatusCode.urlSessionUnexpectedError)
                S3.progress_blocks.removeValue( forKey: req.url!.absoluteString )
                return
            }
            
            do 
            {
                // el fichero se ha descargado a un temporal, hay que moverlo ahora o perderlo para siempre
                print("S3 download finished. Moving from \(fileURL.relativePath) to \(saveFileURL.relativePath)")
                try? FileManager.default.moveItem( at: fileURL, to: saveFileURL )
            }
            catch {
                print ("S3::getFile exception: \(error)")
                completion( nil, error)
                S3.progress_blocks.removeValue( forKey: req.url!.absoluteString )
                return
            }
            
            completion( saveFileURL, nil )
            S3.progress_blocks.removeValue( forKey: req.url!.absoluteString )
        }
        downloadTask.resume()
    }
        
    
    public func putFile ( _ host: String, _ path: String, _ content: Data, progress: S3ProgressCallback?, completion: @escaping S3UploadCompletionCallback )
    {
        var req = fileRequest( .put, host, path )
        req.httpBody = content
        s3_exec_request( &req, host )
     
        S3.progress_blocks[ req.url!.absoluteString ] = progress
        
        let config = URLSessionConfiguration.ephemeral
        let session = URLSession( configuration: config, delegate: self, delegateQueue: .main )
        
        let task = session.dataTask( with: req ) { data, response, error in
            if let error = error {
                print (" S3::putFile error: \(error)")
                completion( nil, error)
                S3.progress_blocks.removeValue( forKey: req.url!.absoluteString )
                return
            }
            guard let responseHttp = response as? HTTPURLResponse,
                (200...299).contains(responseHttp.statusCode) else {
                if let responseHttp = response as? HTTPURLResponse{
                    completion( nil, HTTP_S3_StatusCode(rawValue: responseHttp.statusCode))
                }
                else {
                    completion( nil, HTTP_S3_StatusCode.urlSessionUnexpectedError)
                }
                S3.progress_blocks.removeValue( forKey: req.url!.absoluteString )
                return
            }
            
            if let mimeType = responseHttp.mimeType,
                mimeType == "application/json",
                let data = data,
                let dataString = String(data: data, encoding: .utf8) {
                print (" S3::putFile got data: \(dataString)")
            }
            
            completion( data, nil )
            S3.progress_blocks.removeValue( forKey: req.url!.absoluteString )
        }
        task.resume()
    }
    
    // callback del getFile
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        print("Download progression callback")
        let progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
        if let p = S3.progress_blocks[ downloadTask.currentRequest!.url!.absoluteString ] {
            p?( progress )
        }
    }

    // callback del putFile
    public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        let progress = Float(totalBytesSent) / Float(totalBytesExpectedToSend)
        if let p = S3.progress_blocks[ task.currentRequest!.url!.absoluteString ] {
            p?( progress )
        }
    }
    
}




/// ERRORES para devolver en los callback de completion de los metodos async
/// This is a list of Hypertext Transfer Protocol (HTTP) response status codes.
/// It includes codes from IETF internet standards, other IETF RFCs, other specifications, and some additional commonly used codes.
/// The first digit of the status code specifies one of five classes of response; an HTTP client must recognise these five classes at a minimum.
enum HTTP_S3_StatusCode: Int, Error {
    
    /// The response class representation of status codes, these get grouped by their first digit.
    enum ResponseType {
        
        /// - informational: This class of status code indicates a provisional response, consisting only of the Status-Line and optional headers, and is terminated by an empty line.
        case informational
        
        /// - success: This class of status codes indicates the action requested by the client was received, understood, accepted, and processed successfully.
        case success
        
        /// - redirection: This class of status code indicates the client must take additional action to complete the request.
        case redirection
        
        /// - clientError: This class of status code is intended for situations in which the client seems to have erred.
        case clientError
        
        /// - serverError: This class of status code indicates the server failed to fulfill an apparently valid request.
        case serverError
        
        /// - undefined: The class of the status code cannot be resolved.
        case undefined
    }
    
    //
    // Informational - 1xx
    //
    
    /// - continue: The server has received the request headers and the client should proceed to send the request body.
    case `continue` = 100
    
    /// - switchingProtocols: The requester has asked the server to switch protocols and the server has agreed to do so.
    case switchingProtocols = 101
    
    /// - processing: This code indicates that the server has received and is processing the request, but no response is available yet.
    case processing = 102
    
    //
    // Success - 2xx
    //
    
    /// - ok: Standard response for successful HTTP requests.
    case ok = 200
    
    /// - created: The request has been fulfilled, resulting in the creation of a new resource.
    case created = 201
    
    /// - accepted: The request has been accepted for processing, but the processing has not been completed.
    case accepted = 202
    
    /// - nonAuthoritativeInformation: The server is a transforming proxy (e.g. a Web accelerator) that received a 200 OK from its origin, but is returning a modified version of the origin's response.
    case nonAuthoritativeInformation = 203
    
    /// - noContent: The server successfully processed the request and is not returning any content.
    case noContent = 204
    
    /// - resetContent: The server successfully processed the request, but is not returning any content.
    case resetContent = 205
    
    /// - partialContent: The server is delivering only part of the resource (byte serving) due to a range header sent by the client.
    case partialContent = 206
    
    /// - multiStatus: The message body that follows is an XML message and can contain a number of separate response codes, depending on how many sub-requests were made.
    case multiStatus = 207
    
    /// - alreadyReported: The members of a DAV binding have already been enumerated in a previous reply to this request, and are not being included again.
    case alreadyReported = 208
    
    /// - IMUsed: The server has fulfilled a request for the resource, and the response is a representation of the result of one or more instance-manipulations applied to the current instance.
    case IMUsed = 226
    
    //
    // Redirection - 3xx
    //
    
    /// - multipleChoices: Indicates multiple options for the resource from which the client may choose
    case multipleChoices = 300
    
    /// - movedPermanently: This and all future requests should be directed to the given URI.
    case movedPermanently = 301
    
    /// - found: The resource was found.
    case found = 302
    
    /// - seeOther: The response to the request can be found under another URI using a GET method.
    case seeOther = 303
    
    /// - notModified: Indicates that the resource has not been modified since the version specified by the request headers If-Modified-Since or If-None-Match.
    case notModified = 304
    
    /// - useProxy: The requested resource is available only through a proxy, the address for which is provided in the response.
    case useProxy = 305
    
    /// - switchProxy: No longer used. Originally meant "Subsequent requests should use the specified proxy.
    case switchProxy = 306
    
    /// - temporaryRedirect: The request should be repeated with another URI.
    case temporaryRedirect = 307
    
    /// - permenantRedirect: The request and all future requests should be repeated using another URI.
    case permenantRedirect = 308
    
    //
    // Client Error - 4xx
    //
    
    
    /// - badRequest: The server cannot or will not process the request due to an apparent client error.
    case badRequest = 400
    
    /// - unauthorized: Similar to 403 Forbidden, but specifically for use when authentication is required and has failed or has not yet been provided.
    case unauthorized = 401
    
    /// - paymentRequired: The content available on the server requires payment.
    case paymentRequired = 402
    
    /// - forbidden: The request was a valid request, but the server is refusing to respond to it.
    case forbidden = 403
    
    /// - notFound: The requested resource could not be found but may be available in the future.
    case notFound = 404
    
    /// - methodNotAllowed: A request method is not supported for the requested resource. e.g. a GET request on a form which requires data to be presented via POST
    case methodNotAllowed = 405
    
    /// - notAcceptable: The requested resource is capable of generating only content not acceptable according to the Accept headers sent in the request.
    case notAcceptable = 406
    
    /// - proxyAuthenticationRequired: The client must first authenticate itself with the proxy.
    case proxyAuthenticationRequired = 407
    
    /// - requestTimeout: The server timed out waiting for the request.
    case requestTimeout = 408
    
    /// - conflict: Indicates that the request could not be processed because of conflict in the request, such as an edit conflict between multiple simultaneous updates.
    case conflict = 409
    
    /// - gone: Indicates that the resource requested is no longer available and will not be available again.
    case gone = 410
    
    /// - lengthRequired: The request did not specify the length of its content, which is required by the requested resource.
    case lengthRequired = 411
    
    /// - preconditionFailed: The server does not meet one of the preconditions that the requester put on the request.
    case preconditionFailed = 412
    
    /// - payloadTooLarge: The request is larger than the server is willing or able to process.
    case payloadTooLarge = 413
    
    /// - URITooLong: The URI provided was too long for the server to process.
    case URITooLong = 414
    
    /// - unsupportedMediaType: The request entity has a media type which the server or resource does not support.
    case unsupportedMediaType = 415
    
    /// - rangeNotSatisfiable: The client has asked for a portion of the file (byte serving), but the server cannot supply that portion.
    case rangeNotSatisfiable = 416
    
    /// - expectationFailed: The server cannot meet the requirements of the Expect request-header field.
    case expectationFailed = 417
    
    /// - teapot: This HTTP status is used as an Easter egg in some websites.
    case teapot = 418
    
    /// - misdirectedRequest: The request was directed at a server that is not able to produce a response.
    case misdirectedRequest = 421
    
    /// - unprocessableEntity: The request was well-formed but was unable to be followed due to semantic errors.
    case unprocessableEntity = 422
    
    /// - locked: The resource that is being accessed is locked.
    case locked = 423
    
    /// - failedDependency: The request failed due to failure of a previous request (e.g., a PROPPATCH).
    case failedDependency = 424
    
    /// - upgradeRequired: The client should switch to a different protocol such as TLS/1.0, given in the Upgrade header field.
    case upgradeRequired = 426
    
    /// - preconditionRequired: The origin server requires the request to be conditional.
    case preconditionRequired = 428
    
    /// - tooManyRequests: The user has sent too many requests in a given amount of time.
    case tooManyRequests = 429
    
    /// - requestHeaderFieldsTooLarge: The server is unwilling to process the request because either an individual header field, or all the header fields collectively, are too large.
    case requestHeaderFieldsTooLarge = 431
    
    /// - noResponse: Used to indicate that the server has returned no information to the client and closed the connection.
    case noResponse = 444
    
    /// - unavailableForLegalReasons: A server operator has received a legal demand to deny access to a resource or to a set of resources that includes the requested resource.
    case unavailableForLegalReasons = 451
    
    /// - SSLCertificateError: An expansion of the 400 Bad Request response code, used when the client has provided an invalid client certificate.
    case SSLCertificateError = 495
    
    /// - SSLCertificateRequired: An expansion of the 400 Bad Request response code, used when a client certificate is required but not provided.
    case SSLCertificateRequired = 496
    
    /// - HTTPRequestSentToHTTPSPort: An expansion of the 400 Bad Request response code, used when the client has made a HTTP request to a port listening for HTTPS requests.
    case HTTPRequestSentToHTTPSPort = 497
    
    /// - clientClosedRequest: Used when the client has closed the request before the server could send a response.
    case clientClosedRequest = 499
    
    //
    // Server Error - 5xx
    //
    
    /// - internalServerError: A generic error message, given when an unexpected condition was encountered and no more specific message is suitable.
    case internalServerError = 500
    
    /// - notImplemented: The server either does not recognize the request method, or it lacks the ability to fulfill the request.
    case notImplemented = 501
    
    /// - badGateway: The server was acting as a gateway or proxy and received an invalid response from the upstream server.
    case badGateway = 502
    
    /// - serviceUnavailable: The server is currently unavailable (because it is overloaded or down for maintenance). Generally, this is a temporary state.
    case serviceUnavailable = 503
    
    /// - gatewayTimeout: The server was acting as a gateway or proxy and did not receive a timely response from the upstream server.
    case gatewayTimeout = 504
    
    /// - HTTPVersionNotSupported: The server does not support the HTTP protocol version used in the request.
    case HTTPVersionNotSupported = 505
    
    /// - variantAlsoNegotiates: Transparent content negotiation for the request results in a circular reference.
    case variantAlsoNegotiates = 506
    
    /// - insufficientStorage: The server is unable to store the representation needed to complete the request.
    case insufficientStorage = 507
    
    /// - loopDetected: The server detected an infinite loop while processing the request.
    case loopDetected = 508
    
    /// - notExtended: Further extensions to the request are required for the server to fulfill it.
    case notExtended = 510
    
    /// - networkAuthenticationRequired: The client needs to authenticate to gain network access.
    case networkAuthenticationRequired = 511
    
    /// - errores custom de Dual-Link
    case urlSessionUnexpectedError = 599
    
    /// The class (or group) which the status code belongs to.
    var responseType: ResponseType {
        
        switch self.rawValue {
            
        case 100..<200:
            return .informational
            
        case 200..<300:
            return .success
            
        case 300..<400:
            return .redirection
            
        case 400..<500:
            return .clientError
            
        case 500..<600:
            return .serverError
            
        default:
            return .undefined
            
        }
        
    }
    
}

extension HTTPURLResponse {
    
    var status: HTTP_S3_StatusCode? {
        return HTTP_S3_StatusCode(rawValue: statusCode)
    }
    
}
