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
    
    public override func signRequest ( _ request: Request, _ credentials: Credentials ) {
        _ = request.header( "x-amz-acl", "public-read" )
        
        if request.header( "x-amz-content-sha256" ) == nil {
            _ = request.header( AMZ_CONTENT_SHA256_HEADER, getPayload( request ) )
        }

        super.signRequest( request, credentials )
    }
}
