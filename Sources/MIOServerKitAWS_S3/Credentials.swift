//
//  Credentials.swift
//  MIOServerKitAWS_S3
//
//  Created by David Trallero on 03/09/2020.
//

import Foundation


/**
 * Basic implementation of the AWS Credentials interface that allows callers to
 * pass in the AWS Access Key and AWS Secret Access Key in the constructor.
 */
public class Credentials
{
    private var key    : String
    private var secret : String
    private var token  : String?
    private var expires: Int?

    /**
     * Constructs a new BasicAWSCredentials object, with the specified AWS
     * access key and AWS secret key
     *
     * @param string key     AWS access key ID
     * @param string secret  AWS secret access key
     * @param string token   Security token to use
     * @param int    expires UNIX timestamp for when credentials expire
     */
    public init ( key: String, secret: String, token: String? = nil, expires: Int? = nil )
    {
        self.key     = key.trimmingCharacters(in: .whitespacesAndNewlines)
        self.secret  = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        self.token   = token
        self.expires = expires
    }

//    public static func __set_state(array state)
//    {
//        return new self(
//            state['key'],
//            state['secret'],
//            state['token'],
//            state['expires']
//        );
//    }

    public func getAccessKeyId   ( ) -> String  { return key     }
    public func getSecretKey     ( ) -> String  { return secret  }
    public func getSecurityToken ( ) -> String? { return token   }
    public func getExpiration    ( ) -> Int?    { return expires }

//    public func isExpired ( ) -> Bool {
//        return expires != nil && time() >= expires!
//    }

    public func toArray ( ) -> [ String: Any? ]
    {
        return [ "key"    : key
               , "secret" : secret
               , "token"  : token
               , "expires": expires
               ]
    }

//    public func serialize()
//    {
//        return json_encode(this->toArray());
//    }

//    public func unserialize(serialized)
//    {
//        data = json_decode(serialized, true);
//
//        key = data['key'];
//        secret = data['secret'];
//        token = data['token'];
//        expires = data['expires'];
//    }
}
