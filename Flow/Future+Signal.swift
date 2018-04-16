//
//  Future+Signal.swift
//  Flow
//
//  Created by Måns Bernhardt on 2016-03-22.
//  Copyright © 2016 iZettle. All rights reserved.
//

import Foundation


public extension SignalProvider {
    /// Returns a future that will succeed for when `self` signals its first value, or fail if `self` is terminated.
    /// - Note: If the signal is terminated without an error, the return future will fail with `FutureError.aborted`
    var future: Future<Value> {
        let signal = providedSignal
        return Future<Value> { completion in
            signal.onEventType { eventType in
                switch eventType {
                case .initial: break
                case .event(.value(let value)):
                    completion(.success(value))
                case .event(.end(let error)):
                    completion(.failure(error ?? FutureError.aborted))
                }
            }
        }
    }
}

public extension SignalProvider {
    /// Returns a new signal forwarding the value from the future returned from `transform` unless the future fails, where the returned signal terminates with the future's error.
    /// - Note: If `self` signals a value, any previous future returned from `transform` will be cancelled.
    func mapLatestToFuture<T>(on scheduler: Scheduler = .current, _ transform: @escaping (Value) -> Future<T>) -> FiniteSignal<T> {
        return FiniteSignal(self).flatMapLatest(on: scheduler) { value in
            transform(value).valueSignal
        }
    }
}

public extension Future {
    /// Returns a `Disposable` the will cancel `self` when being disposed.
    /// - Note: The disposable will hold a weak reference to `self` to not delay the deallocation of `self`.
    var disposable: Disposable {
        // A future have at least one strong referene until it's completed or cancelled.
        // By holding a weak reference to self we make sure we won't delay the deallocation of the future when it's done.
        // And canceling a completed future has no effect anyway.
        return Disposer { [weak self] in self?.cancel() }
    }
    
    /// Returns a signal that at the completion of `self` will signal the result.
    var resultSignal: Signal<Result<Value>> {
        return Signal { callback in
            self.onResult(callback).disposable
        }
    }

    /// Returns a signal that at the completion of `self` will signal the success value, unless a failure where the signal will be terminated with that failure error.
    var valueSignal: FiniteSignal<Value> {
        return resultSignal.map { try $0.getValue() }
    }
    
    /// Returns a signal that at the completion of `self` will signal the success value and thereafter terminate the signal, unless a failure where the signal will be terminated with that failure error.
    var valueThenEndSignal: FiniteSignal<Value> {
        return FiniteSignal(onEvent: { callback in
            self.onValue {
                callback(.value($0))
                callback(.end)
            }.onError {
                callback(.end($0))
            }.disposable
        })
    }

    /// Returns a new future, where `signal`'s value is will be set to the success value of `self`.
    @discardableResult
    func bindTo<P: SignalProvider>(_ signal: P) -> Future where P.Value == Value, P.Kind == ReadWrite {
        let signal = signal.providedSignal
        return onValue { signal.value = $0 }
    }
    
    /// Returns a new future, where the success value will be hold until `signal`'s value is or becomes true.
    func hold<S>(until signal: S) -> Future where S: SignalProvider, S.Value == Bool, S.Kind.DropWrite == Read {
        return flatMap { val in
            signal.atOnce().filter { $0 }.future.map { _ in val }
        }
    }
}
