//
//  CryptoHelpers.swift
//  MIOAWSS3
//

import Foundation
import Crypto

public func sha256_hex ( _ data: Data ) -> String {
    return SHA256.hash( data: data ).map { String( format: "%02x", $0 ) }.joined()
}

func hmac_sha256 ( _ string: String, key: SymmetricKey ) -> HMAC<SHA256>.MAC {
    return HMAC<SHA256>.authenticationCode( for: Data( string.utf8 ), using: key )
}

func hex_string ( _ mac: HMAC<SHA256>.MAC ) -> String {
    return mac.map { String( format: "%02x", $0 ) }.joined()
}

// AWS Signature V4 signing key derivation:
// kSecret -> kDate -> kRegion -> kService -> kSigning
func sigv4_signing_key ( shortDate: String, region: String, service: String, secretKey: String ) -> SymmetricKey
{
    let date_key    = hmac_sha256( shortDate, key: SymmetricKey( data: Data( "AWS4\(secretKey)".utf8 ) ) )
    let region_key  = hmac_sha256( region,    key: SymmetricKey( data: Data( date_key ) ) )
    let service_key = hmac_sha256( service,   key: SymmetricKey( data: Data( region_key ) ) )
    let signing_key = hmac_sha256( "aws4_request", key: SymmetricKey( data: Data( service_key ) ) )

    return SymmetricKey( data: Data( signing_key ) )
}
