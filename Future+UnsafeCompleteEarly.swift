//
//  Future+UnsafeCompleteEarly.swift
//  Flow
//
//  Created by Niil Öhlin on 2019-04-08.
//  Copyright © 2019 iZettle. All rights reserved.
//

import Foundation

public extension Future {

    /// Completes the Future early. Useful during testing.
    /// - Note: Do not use in production as the actual result will not send a value.
    func unsafeCompleteEarly(_ result: Result<Value>) {
        completeWithResult(result)
    }
}
