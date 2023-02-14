//
//  Callbacker+Combine.swift
//  Flow
//
//  Created by Carl Ekman on 2023-02-09.
//  Copyright © 2023 PayPal Inc. All rights reserved.
//

import Foundation
#if canImport(Combine)
import Combine

@available(iOS 13.0, macOS 10.15, *)
public extension Publisher {
    /// Performs just link `sink(receiveValue:)`, but the cancellable produced from each received value
    /// will be automatically cancelled once a new value is published. Completion will cancel the last cancellable as well.
    ///
    /// - Intended to be used similarly to `onValueDisposePrevious(_:on:)`.
    func autosink(
        receiveCompletion: @escaping ((Subscribers.Completion<Self.Failure>) -> Void),
        receiveValue: @escaping ((Self.Output) -> AnyCancellable)
    ) -> AnyCancellable {
        var bag = CancelBag()
        var subBag = bag.subset()

        bag += sink(receiveCompletion: { completion in
            subBag.cancel()
            receiveCompletion(completion)
        }, receiveValue: { value in
            subBag.cancel()
            subBag += receiveValue(value)
        })

        return bag.asAnyCancellable
    }
}

@available(iOS 13.0, macOS 10.15, *)
public extension Publisher where Self.Failure == Never {
    /// Performs just link `sink(receiveValue:)`, but the cancellable produced from each received value
    /// will be automatically cancelled once a new value is published, for publishers that never fail.
    ///
    /// - Intended to be used similarly to `onValueDisposePrevious(_:on:)`.
    func autosink(
        receiveValue: @escaping ((Self.Output) -> AnyCancellable)
    ) -> AnyCancellable {
        var bag = CancelBag()
        var subBag = bag.subset()

        bag += sink { value in
            subBag.cancel()
            subBag += receiveValue(value)
        }

        return bag.asAnyCancellable
    }
}

#endif
