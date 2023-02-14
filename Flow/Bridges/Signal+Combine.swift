//
// Copyright © 2023 PayPal Inc. All rights reserved.
//

import Foundation
#if canImport(Combine)
import Combine

extension CoreSignal {
    @available(iOS 13.0, macOS 10.15, *)
    final class SignalPublisher: Publisher, Cancellable {
        typealias Output = Value
        typealias Failure = Error
        
        internal var signal: CoreSignal<Kind, Value>
        internal var bag: CancelBag

        init(signal: CoreSignal<Kind, Value>) {
            self.signal = signal
            self.bag = []
        }

        func receive<S>(
            subscriber: S
        ) where S : Subscriber, Failure == S.Failure, Value == S.Input {
            // Creating our custom subscription instance:
            let subscription = EventSubscription<S>()
            subscription.target = subscriber

            // Attaching our subscription to the subscriber:
            subscriber.receive(subscription: subscription)

            // Collect cancellables when attaching to signal
            bag += signal
                .onValue { subscription.trigger(for: $0) }
                .asAnyCancellable

            if let finiteVersion = signal as? FiniteSignal<Value> {
                bag += finiteVersion.onEvent { event in
                    if case let .end(error) = event {
                        if let error = error {
                            subscription.end(with: error)
                        } else {
                            subscription.end()
                        }
                    }
                }.asAnyCancellable
            }
        }

        func cancel() {
            bag.cancel()
        }

        deinit {
            cancel()
        }
    }
    
    @available(iOS 13.0, macOS 10.15, *)
    final class EventSubscription<Target: Subscriber>: Subscription
        where Target.Input == Value {
        
        var target: Target?

        func request(_ demand: Subscribers.Demand) {}

        func cancel() {
            target = nil
        }

        func end(with error: Target.Failure? = nil) {
            if let error = error {
                _ = target?.receive(completion: .failure(error))
            } else {
                _ = target?.receive(completion: .finished)
            }
        }
        
        func trigger(for value: Value) {
            _ = target?.receive(value)
        }
    }
    
    @available(iOS 13.0, macOS 10.15, *)
    public var asAnyPublisher: AnyPublisher<Value, Error> {
        SignalPublisher(signal: self).eraseToAnyPublisher()
    }
}

#endif
