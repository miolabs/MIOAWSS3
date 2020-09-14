//
//  Request.swift
//  MIOServerKitAWS_S3
//
//  Created by David Trallero on 03/09/2020.
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public class Request {
    var url: URL
    var _body: Data
    var _method: String
    var _headers: [String:String] = [:]
    
    init ( _ method: String, _ url: String, _ content: Data ) {
        self._method = method
        self.url     = URL( string: url )!
        self._body   = content
        _headers[ "Host" ] = "duallink-images.s3.eu-west-1.amazonaws.com"
    }
    
    public func removeHeaders ( _ headers: [ String ] ) -> Request {
        for key in headers {
            _headers.removeValue(forKey: key)
        }
        
        return self
    }
    
    
    public func method ( ) -> String {
        return _method
    }
    
    
    public func path ( ) -> String {
        return url.path
    }
    
    
    public func query ( ) -> [String:String] {
        return [:]
    }
    
    public func body ( ) -> Data {
        return _body
    }
    
    public func header ( _ key: String ) -> String? {
        return _headers[ key ]
    }
    
    
    public func header ( _ key: String, _ value: String ) -> Request {
        _headers[ key ] = value
        return self
    }

    
    public func headers ( ) -> [String: String] {
        return _headers
    }
    
    
    public func isHTTPS ( ) -> Bool {
        return url.scheme == "https"
    }
    
    
    // TODO: MOVE synchronous call from DLDB to some "Core library"
    public func exec ( ) throws -> (Data?,URLResponse?,Error?) {
        var ret_data    : Data?
          , ret_response: URLResponse?
          , ret_error   : Error?
          , semaphore = DispatchSemaphore(value: 0)
          , request   = URLRequest( url: url )

        request.httpMethod          = _method
        request.allHTTPHeaderFields = _headers
        
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil

        let session = URLSession.init(configuration: config)
        
        if ( _method == "PUT" || _method == "POST" ) {
            let task = session.uploadTask(with: request, from: _body) { data, response, error in
                         ret_data     = data
                         ret_response = response
                         ret_error    = error
            
                         semaphore.signal()
                      }
            
            task.resume( )
        } else {
            request.httpBody = _body
            
            let task = session.dataTask(with: request) { data, response, error in
                         ret_data     = data
                         ret_response = response
                         ret_error    = error
            
                         semaphore.signal()
                      }
            
            task.resume()
        }

        _ = semaphore.wait(timeout: .distantFuture)

        return (ret_data, ret_response, ret_error)
    }
}
