//
//  s3.swift
//  MIOServerKitAWS_S3
//
//  Created by David Trallero on 05/09/2020.
//

import Foundation

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
        
        signature.signRequest( req, credentials )
        
        let response = try req.exec( )
        
        return response.2
    }
}
