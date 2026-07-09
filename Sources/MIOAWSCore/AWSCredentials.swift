//
//  AWSCredentials.swift
//  MIOAWSS3
//

import Foundation

public struct AWSCredentials : Sendable
{
    public let accessKey    : String
    public let secretKey    : String
    public let sessionToken : String?

    public init ( accessKey: String, secretKey: String, sessionToken: String? = nil )
    {
        self.accessKey    = accessKey.trimmingCharacters( in: .whitespacesAndNewlines )
        self.secretKey    = secretKey.trimmingCharacters( in: .whitespacesAndNewlines )
        self.sessionToken = sessionToken
    }
}
