//
//  File.swift
//  
//
//  Created by David Trallero on 03/09/2020.
//

import Foundation


public func gmdate ( ) -> String {
    let today    = Date()
//      , delta    = TimeInterval( TimeZone( secondsFromGMT: 0 )!.secondsFromGMT( for: today ) )
//      , gmday    = today.addingTimeInterval( delta )
      , df       = DateFormatter( )
    
    df.timeZone = TimeZone(secondsFromGMT: 0)
    df.dateFormat = "yyyyMMdd'T'HHmmss'Z'" ;
    
    return df.string( from: today )
}
