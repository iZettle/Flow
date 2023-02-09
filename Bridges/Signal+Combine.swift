//
// Copyright © 2023 PayPal Inc. All rights reserved.
//

import Foundation
#if canImport(Combine)
import Combine

extension CoreSignal {
    @available(iOS 13.0, macOS 10.15, *)
    struct ReadSignalPublisher: Publisher {
        func receive<S>(
            subscriber: S
        ) where S : Subscriber, Failure == S.Failure, Value == S.Input {
            // Creating our custom subscription instance:
            let subscription = EventSubscription<S>()
            subscription.target = subscriber
            
            // Attaching our subscription to the subscriber:
            subscriber.receive(subscription: subscription)
            
            bag += signal.onValue { subscription.trigger(for: $0) }
            
            if let finiteVersion = signal as? FiniteSignal<Value> {
                bag += finiteVersion.onEvent { event in
                    if case let .end(error) = event {
                        if let error = error {
                            subscription.end(with: error)
                        } else {
                            subscription.end()
                        }
                    }
                }
            }
        }
        
        typealias Output = Value
        typealias Failure = Error
        
        fileprivate var signal: CoreSignal<Kind, Value>
        fileprivate var bag = DisposeBag()
    }
    
    @available(iOS 13.0, macOS 10.15, *)
    class EventSubscription<Target: Subscriber>: Subscription
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
    func toAnyPublisher() -> AnyPublisher<Value, ReadSignalPublisher.Failure> {
        ReadSignalPublisher(signal: self).eraseToAnyPublisher()
    }
}

#endif
