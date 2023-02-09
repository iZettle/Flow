//
//  CancelBag.swift
//  Flow
//
//  Created by Carl Ekman on 2023-02-09.
//  Copyright © 2023 PayPal Inc. All rights reserved.
//

import Foundation
#if canImport(Combine)
import Combine

/// A type alias for `Set<AnyCancellable>` meant to bridge some of the patterns of `DisposeBag`
/// with modern conventions, like `store(in set: inout Set<AnyCancellable>)`.
@available(iOS 13.0, macOS 10.15, *)
public typealias CancelBag = Set<AnyCancellable>

@available(iOS 13.0, macOS 10.15, *)
extension CancelBag: Cancellable {
    /// Cancel all elements in the set.
    public func cancel() {
        forEach { $0.cancel() }
    }

    /// Cancel all elements and then empty the set.
    public mutating func empty() {
        cancel()
        removeAll()
    }
}

@available(iOS 13.0, macOS 10.15, *)
extension CancelBag {
    init(disposable: Disposable) {
        self.init([disposable.asAnyCancellable])
    }
}

@available(iOS 13.0, macOS 10.15, *)
public func += (cancelBag: inout CancelBag, cancellable: AnyCancellable?) {
    if let cancellable = cancellable {
        cancelBag.insert(cancellable)
    }
}

@available(iOS 13.0, macOS 10.15, *)
public func += (cancelBag: inout CancelBag, cancellation: @escaping () -> Void) {
    cancelBag.insert(AnyCancellable(cancellation))
}

#endif
