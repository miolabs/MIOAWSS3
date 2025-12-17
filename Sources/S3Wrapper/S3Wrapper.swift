//
//  S3Wrapper.swift
//
//
//  Created by Javier Segura Perez on 25/6/24.
//

import Foundation

import AWSS3
import AWSClientRuntime
import SmithyIdentityAPI
import Smithy
import ClientRuntime
import SmithyIdentity
import MIOCoreLogger


public enum S3Error: Error
{
    case message(String)
}

public final class S3Wrapper
{
    private let region:String
    private let key:String
    private let secret:String
        
    private var semaphore = DispatchSemaphore(value: 0)
    
    private var response_error:String?
    private var response_data:Data?
        
    public init( region: String, key: String, secret: String )
    {
        self.region = region
        self.key = key
        self.secret = secret
    }
    
    // MARK: - Download
    
    public func getObject( path:String, bucket:String ) async throws -> Data?
    {
        let safe_path = path.prefix(1) == "/" ? String( path.dropFirst() ) : path
     
        let credentials = AWSCredentialIdentity(accessKey: key, secret: secret )
        let awsCredentialIdentityResolver = try StaticAWSCredentialIdentityResolver(credentials)
        let config = try await S3Client.S3ClientConfiguration(awsCredentialIdentityResolver: awsCredentialIdentityResolver, region: region)
        
        let s3_client = S3Client( config: config )
        
        let input = GetObjectInput( bucket: bucket, key: safe_path )
        let response = try await s3_client.getObject( input: input )
        
        guard let body = response.body,
              let data = try await body.readData() else { return nil }
                
        return data
    }
    
    fileprivate func _get_object_sync( path:String, bucket:String ) throws -> Data?
    {
        DispatchQueue.global().async {
            Task {
                do {
                    let data = try await self.getObject( path: path, bucket: bucket )
                    self.response_data = data
                }
                catch {
                    Log.error( "S3 wrapper error: \(error)" )
                    self.response_error = "\(error)"
                }
                
                self.semaphore.signal()
                
            }
        }
        
        semaphore.wait()
        
        if response_error != nil {
            throw S3Error.message( response_error! )
        }

        return response_data
    }
    
    public func getObject( path:String, bucket:String ) throws -> Data? {
        return try _get_object_sync( path: path, bucket: bucket )
    }
    
    // MARK: - Upload
    
    public func putObject( data:Data, path:String, bucket:String, acl: S3ClientTypes.ObjectCannedACL? = nil ) async throws
    {
        let safe_path = path.prefix(1) == "/" ? String( path.dropFirst() ) : path
     
        let credentials = AWSCredentialIdentity(accessKey: key, secret: secret )
        let awsCredentialIdentityResolver = try StaticAWSCredentialIdentityResolver(credentials)
        let config = try await S3Client.S3ClientConfiguration(awsCredentialIdentityResolver: awsCredentialIdentityResolver, region: region)
        
        
        let s3_client = S3Client( config: config )
        
        let dataStream = ByteStream.data( data )
        
        let input = PutObjectInput( body: dataStream, bucket: bucket, key: safe_path )
        _ = try await s3_client.putObject( input: input )
        
        if acl != nil {
            let acl_input = PutObjectAclInput( acl:acl!, bucket: bucket, key: safe_path )
            let response = try await s3_client.putObjectAcl( input: acl_input )
            Log.debug( "ACL Response: \(response)")
        }
        
    }
    
    fileprivate func _put_object_sync( data:Data, path:String, bucket:String, acl: S3ClientTypes.ObjectCannedACL? = nil ) throws
    {
        DispatchQueue.global().async {
            Task {
                do {
                    Log.trace( "Starting S3 upload: \(path), bucket: \(bucket), acl: \(acl ?? .publicRead)" )
                    try await self.putObject( data: data, path: path, bucket:bucket, acl: acl )
                }
                catch {
                    Log.error( "S3 wrapper error: \(error)" )
                    self.response_error = "\(error)"
                }
                self.semaphore.signal()
            }
        }
        
        semaphore.wait()
        
        if response_error != nil {
            throw S3Error.message( response_error! )
        }
    }
    
    public func putObject( data:Data, path:String, bucket:String, acl: S3ClientTypes.ObjectCannedACL? = nil ) throws {
        try _put_object_sync( data: data, path: path, bucket: bucket, acl: acl )
    }
    
    // MARK: - Deletion
    
    public func deleteObject( path:String, bucket:String) async throws
    {
        let safe_path = path.prefix(1) == "/" ? String( path.dropFirst() ) : path
        
        let credentials = AWSCredentialIdentity(accessKey: key, secret: secret )
        let awsCredentialIdentityResolver = try StaticAWSCredentialIdentityResolver(credentials)
        let config = try await S3Client.S3ClientConfiguration(awsCredentialIdentityResolver: awsCredentialIdentityResolver, region: region)
        
        let s3_client = S3Client( config: config )
        
        let input = DeleteObjectInput( bucket: bucket, key: safe_path )
        _ = try await s3_client.deleteObject( input: input )        
    }
    
    fileprivate func _delete_object_sync( path:String, bucket:String ) throws
    {
        DispatchQueue.global().async {
            Task {
                do {
                    try await self.deleteObject( path: path, bucket: bucket )
                }
                catch {
                    self.response_error = "\(error)"
                    Log.error( "S3 wrapper error: \(error)" )
                }
                self.semaphore.signal()
            }
        }
        
        semaphore.wait()
        
        if response_error != nil {
            throw S3Error.message( response_error! )
        }
    }
    
    public func deleteObject( path:String, bucket:String ) throws {
        try _delete_object_sync( path: path, bucket: bucket )
    }
}
