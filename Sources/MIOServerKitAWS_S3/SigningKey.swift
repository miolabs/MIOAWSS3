//
//  SigningKey.swift
//  
//
//  Created by David Trallero on 03/09/2020.
//

import Foundation
import Crypto

/** @var array Cache of previously signed values */
var g_signing_key_cache: [String:SymmetricKey] = [:]
let g_signing_key_queue = DispatchQueue(label: "com.miolabs.aws_s3.signing_key")

public func createScope ( _ shortDate: String, _ region: String, _ service: String ) -> String
{
    return "\(shortDate)/\(region)/\(service)/aws4_request"
}

public func getSigningKey ( _ shortDate: String, _ region: String, _ service: String, _ secretKey: String ) -> SymmetricKey
{
    let k = shortDate + "_" + region + "_" + service + "_"  + secretKey

    g_signing_key_queue.sync {
        if g_signing_key_cache[ k ] == nil {
            let dateKey    = sha256_hmac( shortDate, "AWS4\(secretKey)".data(using: .utf8 )! )
              , regionKey  = sha256_hmac( region, dateKey )
              , serviceKey = sha256_hmac( service, regionKey )
           
            g_signing_key_cache[ k ] = SymmetricKey( data: sha256_hmac( "aws4_request", serviceKey ) )
        }
    }
    
    return g_signing_key_cache[ k ]!
}
