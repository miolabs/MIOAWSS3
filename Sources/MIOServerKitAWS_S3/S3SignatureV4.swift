//
//  S3SignatureV4.swift
//  MIOServerKitAWS_S3
//
//  Created by David Trallero on 03/09/2020.
//

import Foundation


class S3SignatureV4: SignatureV4
{
    public init ( _ region: String ) {
        super.init( service: "s3", region: region )
    }
    
    public override func signRequest ( _ request: inout URLRequest, _ credentials: Credentials ) {
        request.setValue( "public-read", forHTTPHeaderField: "x-amz-acl")
        
        if request.value( forHTTPHeaderField: "x-amz-content-sha256" ) == nil {
            request.setValue( getPayload( request ), forHTTPHeaderField: AMZ_CONTENT_SHA256_HEADER )
        }

        super.signRequest( &request, credentials )
    }
}
