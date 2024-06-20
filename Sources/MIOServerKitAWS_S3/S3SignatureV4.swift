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
    case `default` = "default"
    case publicRead = "public-read"
}

public enum S3SignatureV4StorageClassType : String
{
    case `default` = "default"
    case reducedRedundancy = "REDUCED_REDUNDANCY"
}


class S3SignatureV4: SignatureV4
{
    var _payload_type:AWS_SIGNATURE_PAYLOAD_TYPE = .UNSIGNED_PAYLOAD
    
    public init ( _ region: String, payloadType: AWS_SIGNATURE_PAYLOAD_TYPE ) {
        _payload_type = payloadType
        super.init( service: "s3", region: region, isUnsigned: (payloadType == .UNSIGNED_PAYLOAD) )
    }
    
    public func signRequest ( _ request: inout URLRequest, _ credentials: Credentials, acl: S3SignatureV4ACLType = .default, storage: S3SignatureV4StorageClassType = .default ) -> String {
        if acl != .default {
            request.setValue( acl.rawValue, forHTTPHeaderField: "x-amz-acl")
        }
        
        if storage != .default {
            request.setValue( storage.rawValue, forHTTPHeaderField: "x-amz-storage-class")
        }
        
//        if request.value( forHTTPHeaderField: "x-amz-content-sha256" ) == nil {
//            request.setValue( getPayload( request ), forHTTPHeaderField: AMZ_CONTENT_SHA256_HEADER )
//        }

        return super.signRequest( &request, credentials, payloadType: _payload_type )
    }
}
