//
//  Future+Additions.swift
//  Flow
//
//  Created by Måns Bernhardt on 2015-10-05.
//  Copyright © 2015 iZettle. All rights reserved.
//

import Foundation

public extension Future {
    /// Creates a new instance already succeeded with `value`.
    convenience init(_ value: Value) {
        self.init(result: .success(value))
    }
    
    /// Creates a new instance already failed with `error`.
    convenience init(error: Error) {
        self.init(result: .failure(error))
    }

    /// Creates a new instance that will complete with the first result from `callbacker`.
    convenience init(callbacker: Callbacker<Result<Value>>) {
        self.init { completion in
            callbacker.addCallback(completion)
        }
    }

    /// Creates a new instance that will complete with the result from executing `immediate`.
    convenience init(on scheduler: Scheduler = .current, immediate: @escaping () throws -> Value) {
        self.init(on: scheduler) { completion in
            try completion(.success(immediate()))
            return NilDisposer()
        }
    }
}

public extension Future {
    /// Returns a new future with the result of calling `transform` with the success value of `self´.
    /// - Note: If `transform` throws, the returned future will fail with the thrown error.
    @discardableResult
    func map<O>(on scheduler: Scheduler = .current, _ transform: @escaping (Value) throws -> O) -> Future<O>  {
        return mapResult(on: scheduler) { result in
            switch result {
            case .success(let value): return try transform(value)
            case .failure(let error): throw error
            }
        }
    }
    
    /// Returns a new future with the result of calling `transform` with the failure error of `self´.
    /// - Note: If `transform` throws, the returned future will fail with the thrown error.
    @discardableResult
    func mapError(on scheduler: Scheduler = .current, _ transform: @escaping (Error) throws -> Value) -> Future  {
        return mapResult(on: scheduler) { result in
            switch result {
            case .success(let value): return value
            case .failure(let error): return try transform(error)
            }
        }
    }
}

public extension Future {
    /// Returns a new future with the result of the future being returned from calling `transform` with the success value of `self´.
    /// - Note: If `transform` throws, the returned future will fail with the thrown error.
    @discardableResult
    func flatMap<O>(on scheduler: Scheduler = .current, _ transform: @escaping (Value) throws -> Future<O>) -> Future<O>  {
        return flatMapResult(on: scheduler) { result in
            switch result {
            case .success(let value): return try transform(value)
            case .failure(let error): return Future<O>(error: error)
            }
        }
    }
    
    /// Returns a new future with the result of the future being returned from calling `transform` with the failure error of `self´.
    /// - Note: If `transform` throws, the returned future will fail with the thrown error.
    @discardableResult
    func flatMapError(on scheduler: Scheduler = .current, _ transform: @escaping (Error) throws -> Future) -> Future  {
        return flatMapResult(on: scheduler) { result in
            switch result {
            case .success(let value): return Future(value)
            case .failure(let error): return try transform(error)
            }
        }
    }
}

public extension Future {
    /// Returns a new future that will call `callback` with the success value of `self`.
    /// - Note: The returned future will maintain the result of `self` unless `callback` throws, where the returned future will fail with the thrown error.
    /// - Note: The returned future will not complete until the call to `callback` has returned.
    @discardableResult
    func onValue(on scheduler: Scheduler = .current, _ callback: @escaping (Value) throws -> ()) -> Future  {
        return onResult(on: scheduler) { result in
            if case .success(let value) = result {
                try callback(value)
            }
        }
    }
    
    /// Returns a new future that will call `callback` with the failure error of `self`.
    /// - Note: The returned future will maintain the result of `self` unless `callback` throws, where the returned future will fail with the thrown error.
    /// - Note: The returned future will not complete until the call to `callback` has returned.
    @discardableResult
    func onError(on scheduler: Scheduler = .current, _ callback: @escaping (Error) throws -> ()) -> Future  {
        return onResult(on: scheduler) { result in
            if case .failure(let error) = result {
                try callback(error)
            }
        }
    }
    
    /// Returns a new future that will call `callback` with the result of `self`.
    /// - Note: The returned future will maintain the result of `self` unless `callback` throws, where the returned future will fail with the thrown error.
    /// - Note: The returned future will not complete until the call to `callback` has returned.
    @discardableResult
    func onResult(on scheduler: Scheduler = .current, _ callback: @escaping (Result<Value>) throws -> ()) -> Future  {
        return mapResult(on: scheduler) { result in
            try callback(result)
            switch result {
            case .success(let value): return value
            case .failure(let error): throw error
            }
        }
    }

}

public extension Future {
    /// Returns a new future that will call `callback` when `self` either completes or is being canceled.
    /// - Note: The returned future will maintain the result of `self` unless `callback` throws, where the returned future will fail with the thrown error.
    /// - Note: The returned future will not complete until the call to `callback` has returned.
    @discardableResult
    public func always(on scheduler: Scheduler = .current, _ callback: @escaping () -> ()) -> Future {
        return onCancel(on: scheduler, callback).onResult(on: scheduler) { _ in callback() }
    }
    
    /// Returns a new future that will call `callback` when `self` either fails with an error or is being canceled.
    /// - Note: The returned future will not complete until the call to `callback` has returned.
    @discardableResult
    func onErrorOrCancel(on scheduler: Scheduler = .current, _ callback: @escaping (Error?) -> ()) -> Future {
        return onError(on: scheduler) { callback($0) }.onCancel(on: scheduler) { callback(nil) }
    }
}

public extension Future {
    /// Returns a new future that will call `callback` with the result of `self`.
    /// - Note: The returned future will maintain the result of `self` unless `callback` throws, or the future retuned from `callback` fails, where the returned future will fail with that error.
    /// - Note: The returned future will not complete until the future returned from `callback` has completed.
    @discardableResult
    func onResultPassItThrough<O>(on scheduler: Scheduler = .current, _ callback: @escaping (Result<Value>) throws -> Future<O>) -> Future {
        return flatMapResult(on: scheduler) { result in
            try callback(result).map { _ in try result.getValue() }
        }
    }
    
    /// Returns a new future that will call `callback` with the success value of `self`.
    /// - Note: The returned future will maintain the result of `self` unless `callback` throws, or the future retuned from `callback` fails, where the returned future will fail with that error.
    /// - Note: The returned future will not complete until the future returned from `callback` has completed.
    @discardableResult
    func onValuePassItThrough<O>(on scheduler: Scheduler = .current, _ callback: @escaping (Value) throws -> Future<O>) -> Future {
        return flatMapResult(on: scheduler) { result in
            switch result {
            case .success(let value):
                return try callback(value).map { _ -> Value in return value }
            case .failure(let error):
                return Future(error: error)
            }
        }
    }

    /// Returns a new future that will call `callback` with the failure error of `self`.
    /// - Note: The returned future will maintain the result of `self` unless `callback` throws, or the future retuned from `callback` fails, where the returned future will fail with that error.
    /// - Note: The returned future will not complete until the future returned from `callback` has completed.
    @discardableResult
    func onErrorPassItThrough<O>(on scheduler: Scheduler = .current, _ callback: @escaping (Error) throws -> Future<O>) -> Future {
        return flatMapResult(on: scheduler) { result in
            switch result {
            case .success(let value):
                return Future(value)
            case .failure(let error):
                return try callback(error).map { _ -> Value in throw error }
            }
        }
    }

    /// Returns a new `Future<Void>` where any success value from `self` is discarded.
    @discardableResult
    func toVoid() -> Future<Void> {
        return map { _ in return Void() }
    }
    
    /// Returns a new future that will not cancel `self` if being canceled
    @discardableResult
    func ignoreCanceling() -> Future {
        return Future { completion, mover in
            mover.moveInside(self).onResult(completion)
            return NilDisposer()
        }
    }
}

public extension Future where Value == () {
    /// Creates a new instance already completed with `()`.
    convenience init() {
        self.init(())
    }

    enum Forever { case forever }
    
    /// Creates a new instance that will never complete.
    /// - Note: Pass `.forever` as an argument: `Future(.forever)`
    convenience init(_ forever: Forever) {
        self.init { _ in NilDisposer() }
    }
}

public extension Future {
    /// Returns a new future that will delay the result of `self` by `delay`.
    /// - Note: A `delay` of zero will still delay the future. However, passing a nil `delay` will not delay the future.
    @discardableResult
    func delay(by delay: TimeInterval?) -> Future {
        guard let delay = delay else { return self.onResult { _ in } } // Make sure to return a new instance
        precondition(delay >= 0)

        return flatMapResult(on: .none) { result in
            Future(on: .none) { completion in
                disposableAsync(after: delay) {
                    completion(result)
                }
            }
        }
    }
    
    /// Will perform `work´ while the future is executing.
    /// - Parameter delay: Delays the execution of `work`.
    /// - Parameter work: The work to be performed. The `Disposable` returned from `work` will be disposed when `self` completes or the returned future is canceled.
    /// - Returns: a new future that will complete when `self` completes.
    ///
    ///     future.performWhile(spinner.animate) // Will run spinner animatation while future is performing.
    ///
    /// - Note: If `self` completes or the returned future is canceled before `delay` seconds, `work` will never be executed.
    /// - Note: A `delay` of zero will still delay calling `work`. However, passing a nil `delay` will execute `work` at once.
    @discardableResult
    func performWhile(on scheduler: Scheduler = .current, delayBy delay: TimeInterval? = nil, _ work: @escaping () -> Disposable) -> Future {
        return Future { completion, mover in
            let future = mover.moveInside(self)
            let bag = DisposeBag(NilDisposer()) // make non-empty

            bag += future.onResult(completion).disposable
            
            guard let delay = delay else {
                let disposable = work()
                bag += {
                    scheduler.async(execute: disposable.dispose) // make sure to schedule disposable as well
                }
                return bag
            }
            
            bag += scheduler.disposableAsync(after: delay) {
                guard !bag.isEmpty else { return } // Already disposed?
                let disposable = work()
                bag += {
                    scheduler.async(execute: disposable.dispose) // make sure to schedule disposable as well
                }
            }
            
            return bag
        }
    }
}

public extension Future {
    /// Returns a new future that will repeat `self` if `predicate`, called with `self`'s result, returns `true`.
    /// - Parameter delayBetweenRepeats: The delay before `self` is being repeated.
    ///   A `delayBetweenRepetitions` of zero will still delay the repeat.
    ///   However, passing a nil `delayBetweenRepetitions` will repeat at once.
    /// - Parameter maxRepetitions: Will never repeat more than `maxRepetitions`, defaults to nil, hence no limit.
    @discardableResult
    func onResultRepeat(on scheduler: Scheduler = .current, delayBetweenRepetitions delay: TimeInterval? = nil, maxRepetitions: Int? = nil, when predicate: @escaping (Result<Value>) -> Bool = { _ in true }) -> Future {
        return onResultRepeat(on: scheduler, maxRepetitions: maxRepetitions) { result in
            Future<Bool>(predicate(result)).delay(by: delay)
        }
    }
    
    /// Returns a new future that will repeat `self` if the future returned from `predicate`, called if `self` fails, completes with `true`.
    /// if `predicateFuture` returned future completes with `true`.
    /// - Parameter maxRepetitions: Will never repeat more than `maxRepetitions`, defaults to nil, hence no limit.
    /// - Parameter predicateFuture: If predicateFuture completes with true the future will be repeated.
    /// - Note: If `predicateFuture`'s returned future completes with `false` or fails, the returned future will succced with the result from `self`.
    @discardableResult
    func onErrorRepeat(on scheduler: Scheduler = .current, maxRepetitions: Int? = nil, when predicateFuture: @escaping (Error) -> Future<Bool>) -> Future {
        return onResultRepeat(on: scheduler, maxRepetitions: maxRepetitions) { result in
            guard let error = result.error else { return Future<Bool>(false) }
            return predicateFuture(error)
        }
    }

    /// Returns a new future that will repeat `self` if the `predicate`, called if `self` fails, returns `true`.
    /// - Parameter delayBetweenRepetitions: The delay before `self` is being repeated.
    ///   A `delayBetweenRepetitions` of zero will still delay the repeat.
    ///   However, passing a nil `delayBetweenRepeats` will repeat at once.
    /// - Parameter maxRepetitions: Will never repeat more than `maxRepetitions`, defaults to nil, hence no limit.
    @discardableResult
    func onErrorRepeat(on scheduler: Scheduler = .current, delayBetweenRepetitions delay: TimeInterval? = nil, maxRepetitions: Int? = nil, when predicate: @escaping (Error) -> Bool = { _ in true }) -> Future {
        return onErrorRepeat(on: scheduler, maxRepetitions: maxRepetitions) { error in
            Future<Bool>(predicate(error))
        }
    }

    /// Returns a new future that will repeat `self` `count` times.
    /// - Parameter delayBetweenRepetitions: The delay before `self` is being repeated.
    ///   A `delayBetweenRepetitions` of zero will still delay the repeat.
    ///   However, passing a nil `delayBetweenRepeats` will repeat at once.
    @discardableResult
    func repeatAndCollect(repeatCount count: NSInteger, delayBetweenRepetitions delay: TimeInterval? = nil) -> Future<[Value]> {
        let s = StateAndCallback(state: (count: count, result: [Value]()))
        
        return onResultRepeat(on: .none, delayBetweenRepetitions: delay) { result in
            guard case .success(let value) = result else { return false }
            s.lock()
            s.val.result.append(value)
            defer {
                s.val.count -= 1
                s.unlock()
            }
            return s.val.count > 0
        }.map(on: .none) { _ in s.protectedVal.result }.always(on: .none) {
             // If being repeated, make sure to reset values
            s.lock()
            s.val.count = count
            s.val.result = []
            s.unlock()
        }
    }

    /// Will return a new future that will replace `self`'s result with a success `value` if `self` does not complete before `timeout`
    @discardableResult
    func succeed(with value: Value, after timeout: TimeInterval) -> Future {
        return replace(with: .success(value), after: timeout)
    }
    
    /// Will return a new future that will replace `self`'s result with a failure `error` if `self` does not complete before `timeout`
    @discardableResult
    func fail(with error: Error, after timeout: TimeInterval) -> Future {
        return replace(with: .failure(error), after: timeout)
    }
}
