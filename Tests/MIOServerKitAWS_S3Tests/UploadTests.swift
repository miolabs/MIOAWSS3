//
//  UploadTests.swift
//
//
//  Created by Javier Segura Perez on 13/6/24.
//

import XCTest
@testable import MIOServerKitAWS_S3

let AWS_ACCESS_KEY_ID = "AKIAIOSFODNN7EXAMPLE"
let AWS_SECRET_ACCESS_KEY = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
let AWS_BUCKET_NAME = "examplebucket"
let AWS_REGION = "us-east-1"
let FILE_NAME = "chunkObject.txt"
let FILE_CONTENT = Data( repeating: 97, count: 65 * 1024 )

func testAuthSignature() {
    
}

func testPutObjectSignature() {
    
}


func testPutObject() {
    
}
