//
//  File.swift
//  
//
//  Created by David Trallero on 03/09/2020.
//

import Foundation
import Crypto


public func sha256_hmac<D:ContiguousBytes> ( _ str: String, _ key: D ) -> HMAC<SHA256>.MAC  {
    return HMAC<SHA256>.authenticationCode( for: [UInt8](str.utf8), using: SymmetricKey(data:key) )
}

public func sha256_hmac ( _ str: String, key: SymmetricKey ) -> HMAC<SHA256>.MAC {
    return HMAC<SHA256>.authenticationCode( for: [UInt8](str.utf8), using: key )
}


// let hashString = hashed.compactMap { String(format: "%02x", $0) }.joined() ??
func sha256_hash ( _ data : Data ) -> String {
    return SHA256.hash(data: data).map{ String(format: "%02x", $0) }.joined()
}



//func hexdigest<D> ( _ data: D ) -> String {
//    return data.map{ String(format: "%02x", $0) }.joined()
//}
