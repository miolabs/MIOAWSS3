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
        return try exec_request( &req, host )
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

public typealias S3ProgressBlock = (Float) -> Void
public typealias S3CompletionBlock = (Data?, Error?) -> Void

extension S3 : URLSessionTaskDelegate
{
    static var progress_blocks:[ String: S3ProgressBlock? ] = [:]
    
    public func putFile ( _ host: String, _ path: String, _ content: Data, progress: S3ProgressBlock?, completion: @escaping S3CompletionBlock )
    {
        var req = fileRequest( .put, host, path )
        req.httpBody = content
        s3_exec_request( &req, host )
     
        S3.progress_blocks[ req.url!.absoluteString ] = progress
        
        let config = URLSessionConfiguration.ephemeral
        let session = URLSession( configuration: config, delegate: self, delegateQueue: .main )
        
        let task = session.dataTask( with: req ) { data, response, error in
            if let error = error {
                print ("error: \(error)")
                return
            }
            guard let response = response as? HTTPURLResponse,
                (200...299).contains(response.statusCode) else {
                print ("server error")
                completion( nil, nil)
                S3.progress_blocks.removeValue( forKey: req.url!.absoluteString )
                return
            }
            
            if let mimeType = response.mimeType,
                mimeType == "application/json",
                let data = data,
                let dataString = String(data: data, encoding: .utf8) {
                print ("got data: \(dataString)")
            }
            
            completion( data, nil )
            S3.progress_blocks.removeValue( forKey: req.url!.absoluteString )
        }
        task.resume()
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        let progress = Float(totalBytesSent) / Float(totalBytesExpectedToSend)
        if let p = S3.progress_blocks[ task.currentRequest!.url!.absoluteString ] {
            p?( progress )
        }
         
    }
}
