//
//  NotificationCenter+Publisher.swift
//  Flow
//
//  Created by Nataliya Patsovska on 2019-06-09.
//  Copyright © 2019 iZettle. All rights reserved.
//

import Foundation
import Combine

@available(iOS 13.0, *)
public extension NotificationCenter {
    func publisher(for name: Notification.Name?, object: Any? = nil) -> Publisher {
        return Publisher(center: self, name: name, object: object)
    }

    struct Publisher: Combine.Publisher {
        public typealias Output = Notification
        public typealias Failure = Never

        var center: NotificationCenter
        var name: Notification.Name?
        var object: Any?

        init(center: NotificationCenter, name: Notification.Name?, object: Any? = nil) {
            self.center = center
            self.name = name
            self.object = object
        }

        public func receive<S>(subscriber: S) where S: Subscriber, Publisher.Failure == S.Failure, Publisher.Output == S.Input {
            let observer = center.addObserver(forName: name, object: object, queue: nil) { note in
                let demand = subscriber.receive(note)
                if demand.max != nil {
                    // not sure how/if I need to handle
                }
            }
            subscriber.onCancel { [weak center] in
                center?.removeObserver(observer)
            }
        }
    }
}

@available(iOS 13.0, *)
public extension Subscriber {
    // Looks like a workaround for something that we're used to doing. Not sure if that's the intended use.
    func onCancel(_ cancel: @escaping () -> Void) {
        receive(subscription: SubscriptionCancellation(cancellable: AnyCancellable(cancel)))
    }
}

// Taken from Rui Peres and Serg Dort: https://twitter.com/peres/status/1135970931153821696
@available(iOS 13.0, *)
private class SubscriptionCancellation: Subscription {
    private let cancellable: Cancellable

    init(cancellable: Cancellable) {
        self.cancellable = cancellable
    }

    func cancel() {
        cancellable.cancel()
    }

    func request(_ demand: Subscribers.Demand) { }
}
