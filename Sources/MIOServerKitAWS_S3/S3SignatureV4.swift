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
    var _payload_type:AWS_SIGNATURE_PAYLOAD_TYPE = .unsigned
    
    public init ( _ region: String, isUnsigned:Bool = false ) {
        super.init( service: "s3", region: region, isUnsigned: isUnsigned )
    }
    
    /*
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
     */
    
    let empty_hash = sha256_hash( Data() )
    
    public func generateChunkBodyString( previousSignature:String, data:Data?, context:SigContext ) -> String
    {
        let bodyString = """
        \(context.payloadType != .multipleChunk ? "AWS4-HMAC-SHA256" : "AWS4-HMAC-SHA256-PAYLOAD" )
        \(context.date)
        \(context.scope)
        \(previousSignature)
        \(empty_hash)
        \( data != nil ? sha256_hash( data! ) : empty_hash )
        """

        return bodyString
    }
    
    public func generateChunkBodySignature( bodyString:String, context:SigContext ) -> String
    {
        let ldt        = context.date
        let sdt        = String( ldt[ ldt.startIndex ... ldt.index( ldt.startIndex, offsetBy: 7 ) ] ) // 20200905
        let signingKey = getSigningKey( sdt, region, service, context.credentials.getSecretKey() )
        let signature  = sha256_hmac( bodyString, key: signingKey ).map{ String(format: "%02x", $0) }.joined()
        
        return signature
    }
    
    public func generateChunkBody( data:Data, signature:String, context:SigContext ) -> (String,Data)
    {    // string(IntHexBase(chunk-size)) + ";chunk-signature=" + signature + \r\n + chunk-data + \r\n
    
        let meta = String(data.count, radix: 16, uppercase: false) + ";chunk-signature=" + signature + "\r\n"
        let body = meta.data(using: .utf8)! + data + "\r\n".data(using: .utf8)!
        
        return ( meta, body )
    }
    
}
