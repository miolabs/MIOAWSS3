//
//  s3.swift
//  MIOServerKitAWS_S3
//
//  Created by David Trallero on 05/09/2020.
//

import Foundation
import MIOCore


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
    
    
    public func putFile ( _ path: String, _ content: Data ) throws -> Error? {
        let url = "https://" + apn + "-" + accountID + ".s3-accesspoint." + region + ".amazonaws.com" + path
          , req = Request( "PUT", url, content )
          , signature = S3SignatureV4( region )
        
        req.header("Host", "duallink-images.s3.eu-west-1.amazonaws.com" )
        
        signature.signRequest( req, credentials )
        
        let response = try req.exec( )
        
        // .2 is Error
        if response.2 != nil { return response.2 }
        
        // In case of no error, response.0 may contain an "Error"
        if response.0 != nil && response.0?.count ?? 0 > 0 {
            let xmlDict = try XMLSerialization.xmlObject(with: response.0!, options: []) as! [String:Any]
            
            if xmlDict[ "__XML_TAG_NAME__" ] as? String == "Error" {
                return AWSError.error( xmlDict[ "Code" ] as? String ?? "Unkown CODE"
                                     , xmlDict[ "Message" ] as? String ?? "Missing Message" )
            }
        }

        return nil
    }
}
