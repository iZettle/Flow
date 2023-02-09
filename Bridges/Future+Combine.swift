//
// Copyright © 2023 PayPal Inc. All rights reserved.
//

import Foundation
#if canImport(Combine)
import Combine

extension Flow.Future {
    @available(iOS 13.0, macOS 10.15, *)
    func toCombineFuture() -> Combine.Future<Value, Error> {
        Combine.Future { promise in
            self.onResult { promise($0) }
        }
    }
}

#endif
