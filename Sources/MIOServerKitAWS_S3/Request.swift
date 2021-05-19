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

public enum RequestError: Error
{
    case bodyIsNil
}

extension RequestError: LocalizedError {
    public var errorDescription: String? {
        switch self {
            case .bodyIsNil:
                return "[Request Error] Body cannot be nil"
        }
    }
}


public class Request {
    var _url: String
    var _body: Data?
    var _method: String
    var _headers: [String:String] = [:]

    var _get_url: URLComponents? = nil
    
    public init ( _ method: String, _ url: String, _ content: Data? = nil ) {
        self._method = method
        self._url    = url
        self._body   = content
        self._get_url = method == "GET" ? URLComponents(string: url)! : nil
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
    
    public var url: URL {
        get {
            return _method == "GET" ?
                   _get_url!.url!
                 : URL( string: _url )!
        }
    }
    
    public func path ( ) -> String {
        return url.path
    }
    
    
    public func query ( ) -> [String:String] { return [:] }
    
    public func param ( _ key: String, _ value: String? ) {
        if _get_url!.queryItems == nil { _get_url!.queryItems = [] }
            
        _get_url!.queryItems!.append( URLQueryItem(name: key, value: value) )
    }
    
    public func body ( ) -> Data? {
        return _body
    }
    
    public func header ( _ key: String ) -> String? {
        return _headers[ key ]
    }
    
    
    @discardableResult public func header ( _ key: String, _ value: String ) -> Request {
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
            if _body == nil {
                throw RequestError.bodyIsNil
            }
            
            let task = session.uploadTask(with: request, from: _body!) { data, response, error in
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
