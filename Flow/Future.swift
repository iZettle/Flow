//
//  Future.swift
//  Flow
//
//  Created by Måns Bernhardt on 2015-09-30.
//  Copyright © 2015 iZettle. All rights reserved.
//

import Foundation


/// An encapsulation of a result that might not yet has been generated.
///
/// A future represents a future result, a result that might take time to asynchronously produce.
/// A future runs its operation only once. This means that it might already be completed by the time
/// one receive an instance of it. This should not affect any logic or functionality based on futures.
///
/// To extract the result of a future you have to provide a closure to be executed once the result is available (which could be at once).
///
///     let future = ...
///     future.onResult { result in
///          // act on the result.
///     }
///
/// Transformations
/// ---------------
///
/// It is often useful to perform transforms on futures, such as mapping the result. Every time such a transform is
/// performed a new future representing this transform is returned. This means you could chain several transforms after
/// each other.
///
///     let future = doSomething().map { $0 * 2 }.onValue { print($0) }
///
/// A future will always execute no matter if anybody will listen on its result. It will always execute just once,
/// and is internally either in the state of waiting for a result or completed with a result.
///
/// Cancelation
/// -----------
///
/// A future can be canceled by calling `cancel()` on it. However `cancel()` will fail if the future is already completed or has continuations (someone listening on its result).
///
/// Scheduling
/// ----------
///
/// For most `Future` APIs accepting a callback closure, there is a defaulted `scheduler` parameter you could pass as well used to schedule
/// the provided callback closure. By default this scheduler is set to the current scheduler used when calling the API.
///
///     future.map { /* Will be called back on the current scheduler at the time `map` was called. */ }
///     future.map(on: .main) { /* Will be called back on the main queue no matter from where `map` was called.  */ }
public final class Future<Value> {
    // Adding special treatment of the one listner (the most common one) improves performance a lot
    private enum State {
        case noListeners(Disposable)
        case oneListener(Disposable, Key, (Result<Value>) -> Void)
        case multipleListeners(Disposable, [Key: (Result<Value>) -> Void])
        case completed(Result<Value>)
    }
    
    private var state: State
    private let clone: () -> Future
    private var _mutex = pthread_mutex_t()

    /// Helper used to move external futures inside `Future.init`'s `onComplete` closure. Needed for repetition to work properly.
    public struct Mover {
        fileprivate let shouldClone: Bool

        /// Move an external `future` inside a `Future.init`'s `onComplete` closure.
        public func moveInside<T>(_ future: Future<T>) -> Future<T> {
            guard shouldClone else { return future }
            return future.clone()
        }
    }

    /// Creates a new instance that will complete when the completion closure passed to `onComplete` is called with a `Result`.
    ///
    /// This is the more advanced versoin of creating a future, where a `Mover` is passed to `onComplete` callback as well. It is rare that you would
    /// need to use this version instead of the more simple one (where a `Mover` is not passed into the closure).
    /// But if you are creating more advanced transforms where futures, created outside the callback, is used inside the callback,
    /// you need to use the `Mover`'s `moveInside` method to move these externally created futures inside this future.
    /// This is neccessary to make repetition of this newly created future to work proplerly.
    ///
    ///     extension Future {
    ///       @discardableResult
    ///       func replace(with result: Result<Value>, after timeout: TimeInterval) -> Future {
    ///         return Future { completion, mover in
    ///           /// As `self` is moved inside this new future, `mover.moveInside` need to be called to allow `self` to restart upon repeting this new future.
    ///           let f = mover.moveInside(self).onResult(completion)
    ///           return Scheduler.concurrentBackground.disposableAsync(after: timeout) {
    ///             f.cancel()
    ///             completion(result)
    ///           }
    ///         }
    ///       }
    ///     }
    ///
    /// - Note: The `onComplete` closure will called back immediately and once for every repetition of `self`.
    ///
    /// - Parameter onComplete: Will be called back with a completion closure (and a mover) to be called with the `Result` of the async operation.
    ///   The `Disposable` returned from `onComplete` will be called when completed or canceled.
    ///   The `Mover` passed back should be used to move externally created futures inside this future.
    public init(on scheduler: Scheduler = .current, onResult: @escaping (@escaping (Result<Value>) -> Void, Mover) throws -> Disposable) {
        OSAtomicIncrement32(&futureUnitTestAliveCount)
        memPrint("Future init", futureUnitTestAliveCount)
        
        state = .noListeners(NilDisposer())
        clone = {
            Future(on: scheduler) { completion, _ in
                try onResult(completion, Mover(shouldClone: true))
            }
        }
        mutex.initialize()
        
        scheduler.async {
            do {
                let disposer = try onResult(self.completeWithResult, Mover(shouldClone: false))

                self.lock()
                
                // If we have not already been completed while calling `function`, store the returned disposer.
                switch self.state {
                case .noListeners:
                    self.state = .noListeners(disposer)
                    self.unlock()
                case .oneListener(_, let k, let c):
                    self.state = .oneListener(disposer, k, c)
                    self.unlock()
                case .multipleListeners(_, let cs):
                    self.state = .multipleListeners(disposer, cs)
                    self.unlock()
                case .completed: // ... otherwise we are already done and should dispose()
                    self.unlock()
                    disposer.dispose()
                }
            } catch {
                self.completeWithResult(.failure(error))
            }
        }
    }
    
    /// Creates a new instance already completed with `result`.
    public init(result: Result<Value>) {
        OSAtomicIncrement32(&futureUnitTestAliveCount)
        memPrint("Future init", futureUnitTestAliveCount)
        
        state = .completed(result)
        clone = { Future(result: result) }
        mutex.initialize()
    }
    
    deinit {
        OSAtomicDecrement32(&futureUnitTestAliveCount)
        memPrint("Future deinit", futureUnitTestAliveCount)
        mutex.deinitialize()
    }
}

public extension Future {
    /// Creates a new instance that will complete when the completion closure passed to `onComplete` is called with a `Result`.
    ///
    ///     extension URLSession {
    ///       func data(at url: URL) -> Future<Data> {
    ///         return Future { completion in
    ///           let task = dataTask(with: url) { data, _, error in
    ///             if let error = error {
    ///               completion(.failure(error))
    ///             } else {
    ///               completion(.success(data!))
    ///             }
    ///           }
    ///           task.resume()
    ///           return Disposer { task.cancel() }
    ///         }
    ///       }
    ///     }
    ///
    /// - Parameter onComplete: Will be called back with a completion closure to be called with the `Result` of the async operation.
    ///   The `Disposable` returned from `onComplete` will be called when completed or canceled.
    convenience init(on scheduler: Scheduler = .current, onResult: @escaping (@escaping (Result<Value>) -> Void) throws -> Disposable) {
        self.init(on: scheduler) { completion, _ in
            try onResult(completion)
        }
    }
}

public extension Future {
    /// Returns a new future with the result of the future being returned from calling `transform` with the result of `self´.
    /// - Note: If `transform` throws, the returned future will fail with the throwned error.
    @discardableResult
    func flatMapResult<O>(on scheduler: Scheduler = .current, _ transform: @escaping (Result<Value>) throws -> Future<O>) -> Future<O> {
        return Future<O>(on: .none) { completion, mover in
            let bag = DisposeBag()
            bag += mover.moveInside(self).onComplete { result in
                scheduler.async {
                    do {
                        bag += try transform(result).onComplete(completion)
                    } catch {
                        completion(.failure(error))
                    }
                }
            }
            return bag
        }
    }
    
    /// Returns a new future with the result of calling `transform` with the result of `self´.
    /// - Note: If `transform` throws, the returned future will fail with the thrown error.
    @discardableResult
    func mapResult<O>(on scheduler: Scheduler = .current, _ transform: @escaping (Result<Value>) throws -> O) -> Future<O> {
        return Future<O>(on: .none) { completion, mover in
            mover.moveInside(self).onComplete { result in
                scheduler.async {
                    do {
                        try completion(.success(transform(result)))
                    } catch {
                        completion(.failure(error))
                    }
                }
            }
        }
    }
}

public enum FutureError: String, Error {
    case aborted
}

public extension Future {
    /// Will cancel the future unless the future is already completed or has continuations.
    /// - Note: All predecessors futures (futures which self was composited from) will be canceled as well.
    /// - Note: Continuing any canceled future will complete with a `.failure(FutureError.aborted)`
    /// - Note: If the future has any continuations (any transforms applied to it and hence other users), the cancel will be ignored.
    func cancel() {
        guard case .noListeners = protectedState else { return }
        
        completeWithResult(.failure(FutureError.aborted))
    }
    
    /// Returns a new future where `callback` will be called if the returned future is canceled.
    @discardableResult
    func onCancel(on scheduler: Scheduler = .current, _ callback: @escaping () -> Void) -> Future {
        return Future<Value>(on: .none) { completion, mover in
            let clone = mover.moveInside(self)
            let disposer = clone.onComplete(completion)
            
            return Disposer {
                if case .completed = clone.protectedState {
                    disposer.dispose()
                } else {
                    disposer.dispose() // Make sure to dispose first to trigger preceeding future's onCancel...
                    scheduler.async(execute: callback) // ...and then call the callback for this onCancel
                }
            }
        }
    }
}

public extension Future {
    /// Returns a new future that will repeat `self` if the future returned from `predicate`, called if `self`'s result, completes with `true`.
    /// if `predicateFuture` returned future completes with `true`.
    /// - Parameter maxRepetitions: Will never repeat more than `maxRepetitions`, defaults to nil, hence no limit.
    /// - Parameter predicateFuture: If predicateFuture completes with true the future will be repeated.
    /// - Note: If `predicateFuture`'s returned future completes with `false` or fails, the returned future will succced with the result from `self`.
    @discardableResult
    func onResultRepeat(on scheduler: Scheduler = .current, maxRepetitions: Int? = nil, when predicateFuture: @escaping (Result<Value>) -> Future<Bool>) -> Future {
        return Future(on: scheduler) { completion, mover in
            let s = StateAndCallback(state: 0, callback: completion)

            func predicate(_ result: Result<Value>) -> Future<Bool> {
                s.lock()
                if let maxRepetitions = maxRepetitions, s.val >= maxRepetitions {
                    s.unlock()
                    return Future<Bool>(false)
                }
                s.val += 1
                s.unlock()
                return predicateFuture(result)
            }
            
            let exec: (Future) -> () = recursive { future, exec in
                var future = future
                var pf: Future<Bool>? = nil
                
                // Avoid recursion (and stack overflows) if both self of predicateFuture has immediate results.
                while true {
                    pf = nil
                    guard case let .completed(r) = future.protectedState else { break }
                    pf = predicate(r)
                    guard let s = pf?.protectedState, case let .completed(r2) = s, r2.value == true else { break }
                    future = self.clone()
                }
                
                let f = future.flatMapResult(on: scheduler) { result -> Future<Bool> in
                    return (pf ?? predicate(result)).onValue(on: .none) { shouldRepeat in
                        guard shouldRepeat else { return s.callback(result) }
                        exec(self.clone())
                    }.onError(on: .none) { e in
                        return s.callback(result)
                    }
                }

                s += Disposer { [weak f] in f?.cancel() }
            }
            
            exec(mover.moveInside(self))
            s += Disposer { _ = exec } // hold on to reference
            
            return s
        }
    }
    
    /// Returns a new future that will replace `self`'s result with `result` if `self` does not complete before `timeout`.
    @discardableResult
    func replace(with result: Result<Value>, after timeout: TimeInterval) -> Future {
        return Future(on: .none) { completion, mover in
            let f = mover.moveInside(self).onResult(completion)
            return disposableAsync(after: timeout) {
                f.cancel()
                completion(result)
            }
        }
    }
}

var futureUnitTestAliveCount: Int32 = 0

func memPrint(_ str: String, _ count: Int32) {
    //print(str, count)
}

private extension Future {
    var mutex: PThreadMutex { return PThreadMutex(&_mutex) }

    private var protectedState: State {
        return mutex.protect { state }
    }
    
    func lock() {
        mutex.lock()
    }
    
    func unlock() {
        mutex.unlock()
    }

    func completeWithResult(_ result: Result<Value>) {
        lock()
        let state = self.state
        
        if case .completed = state {
            unlock()
            return
        }
        
        self.state = .completed(result)
        
        unlock()
        
        switch state {
        case .noListeners(let d):
            d.dispose()
        case .oneListener(let d, _, let c):
            d.dispose()
            c(result)
        case .multipleListeners(let d, let cs):
            d.dispose()
            for c in cs.values {
                c(result)
            }
        case .completed:
            return
        }
    }
    
    /// Returns a disposable to be called on dispose or cancel. If it was the last onComplete being disposed the future itself will be disposed.
    func onComplete(_ completion: @escaping (Result<Value>) -> Void) -> Disposable {
        lock()
        defer { unlock() }
        
        let state = self.state
        switch state {
        case .noListeners(let d):
            let key = generateKey()
            self.state = .oneListener(d, key, completion)
            return NoLockKeyDisposer(key, self.remove)
        case .oneListener(let d, let k, let c):
            let key = generateKey()
            self.state = .multipleListeners(d, [k: c, key: completion])
            return NoLockKeyDisposer(key, self.remove)
        case .multipleListeners(let d, var cs):
            self.state = .noListeners(d) // let go of reference to cs to allow modification to not cause copy-on-write
            let key = generateKey()
            cs[key] = completion
            self.state = .multipleListeners(d, cs)
            return NoLockKeyDisposer(key, self.remove)
        case .completed(let result):
            unlock()
            completion(result)
            lock()
            return NilDisposer()
        }
    }
    
    func remove(for key: Key) {
        lock()
        
        switch state {
        case .noListeners:
            fatalError()
        case .oneListener(let d, let k, _) where k == key:
            state = .completed(.failure(FutureError.aborted))
            unlock()
            d.dispose()
        case .multipleListeners(let d, var cs):
            state = .noListeners(d) // let go of reference to cs to allow modification to not cause copy-on-write
            cs.removeValue(forKey: key)
            if cs.isEmpty {
                state = .completed(.failure(FutureError.aborted))
                unlock()
                d.dispose()
            } else {
                state = .multipleListeners(d, cs)
                unlock()
            }
        case .completed, .oneListener: // oneListener: trying to remove the key a second time (NoLockKeyDisposer can be called more than once)
            unlock()
        }
    }
}

