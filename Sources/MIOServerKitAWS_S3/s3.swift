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

public class S3
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
    
    
    public func putFile ( _ host: String, _ path: String, _ content: Data ) throws -> Error? {
        print("S3: \(host) \(path): \(content)")
        var req = URLRequest(method: "PUT", urlString: api_url( path ),body: content )
        return try exec_request( &req, host )
    }
    
    func api_url ( _ path: String ) -> String {
        return "https://" + apn + "-" + accountID + ".s3-accesspoint." + region + ".amazonaws.com" + path
    }
    
    func exec_request ( _ req: inout URLRequest, _ host: String ) throws -> Error? {
        let signature = S3SignatureV4( region )
        
        req.setValue( host, forHTTPHeaderField: "Host")
  
        signature.signRequest( &req, credentials )
  
        return try dispatch_response( try MIOCoreURLDataRequest_sync( req ) )
    }
    
    func dispatch_response ( _ response: Data? ) throws -> Error? {
        if response == nil || response!.isEmpty { return nil }

        let xmlDict = try XMLSerialization.xmlObject(with: response!, options: []) as! [String:Any]
        print("S3: Response \(xmlDict)")
        if xmlDict[ "__XML_TAG_NAME__" ] as? String == "Error" {
            return AWSError.error( xmlDict[ "Code" ] as? String ?? "Unkown CODE"
                                 , xmlDict[ "Message" ] as? String ?? "Missing Message" )
        }

        return nil
    }

    public func deleteFile ( _ bucket: String, _ path: String ) throws -> Error? {
        var req = URLRequest( method:"DELETE", urlString: api_url( path ) )
        return try exec_request( &req, bucket )
    }
}
