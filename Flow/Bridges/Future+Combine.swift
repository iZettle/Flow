//
// Copyright © 2023 PayPal Inc. All rights reserved.
//

import Foundation
#if canImport(Combine)
import Combine

@available(iOS 13.0, macOS 10.15, *)
extension Flow.Future {
    /// Convert a `Flow.Future<Value>` to a `Combine.Future<Value, Error>` intended to be
    /// used to bridge between the `Flow` and `Combine` world
    public var toCombineFuture: Combine.Future<Value, Error> {
        Combine.Future { promise in
            self.onResult { promise($0) }
        }
    }
}

#endif
