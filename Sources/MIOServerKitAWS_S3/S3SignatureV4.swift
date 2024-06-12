//
//  S3SignatureV4.swift
//  MIOServerKitAWS_S3
//
//  Created by David Trallero on 03/09/2020.
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum S3SignatureV4ACLType : String
{
    case publicRead = "public-read"
}

class S3SignatureV4: SignatureV4
{
    public init ( _ region: String, isUnsigned:Bool = false ) {
        super.init( service: "s3", region: region, isUnsigned: isUnsigned )
    }
    
    public func signRequest ( _ request: inout URLRequest, _ credentials: Credentials, body:Data?, acl: S3SignatureV4ACLType ) {
        request.setValue( acl.rawValue, forHTTPHeaderField: "x-amz-acl")
        
//        if request.value( forHTTPHeaderField: "x-amz-content-sha256" ) == nil {
//            request.setValue( getPayload( request ), forHTTPHeaderField: AMZ_CONTENT_SHA256_HEADER )
//        }

        super.signRequest( &request, credentials, body: body )
    }
}
