//
//  Disposable+Cancellable.swift
//  Flow
//
//  Created by Carl Ekman on 2023-02-09.
//  Copyright © 2023 PayPal Inc. All rights reserved.
//

import Foundation
#if canImport(Combine)
import Combine

@available(iOS 13.0, macOS 10.15, *)
extension Disposable {
    var asAnyCancellable: AnyCancellable {
        AnyCancellable { self.dispose() }
    }
}

@available(iOS 13.0, macOS 10.15, *)
extension Future {
    var cancellable: AnyCancellable {
        AnyCancellable { self.disposable.dispose() }
    }
}

#endif
