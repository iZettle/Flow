//
//  Future+Combiners.swift
//  Flow
//
//  Created by Måns Bernhardt on 2015-09-30.
//  Copyright © 2015 iZettle. All rights reserved.
//

import Foundation


public extension Future {
    /// Returns a new future joining `self` and `other`. If both `self` and `other` succeed, the returned future will succeed with both's results. If either `self` or `other` fails, the returned future will fail as well.
    /// - Parameter cancelNonCompleted: If true (default), as the returned future completes, `self` and `other` will be canceled if possible.
    @discardableResult
    func join<T>(with other: Future<T>, cancelNonCompleted: Bool = true) -> Future<(Value, T)> {
        return Future<(Value, T)> { completion, mover in
            let s = StateAndCallback(state: (left: Value?.none, right: T?.none), callback: completion)
            
            let leftFuture = mover.moveInside(self).onError(on: .none) { completion(.failure($0)) }.onValue { l in
                s.lock()
                s.val.left = l
                guard let r = s.val.right else { return s.unlock() }
                
                s.unlock()
                s.callback(.success((l, r)))
            }
            
            let rightFuture = mover.moveInside(other).onError(on: .none) { completion(.failure($0)) }.onValue { r in
                s.lock()
                s.val.right = r
                guard let l = s.val.left else { return s.unlock() }
                
                s.unlock()
                s.callback(.success((l, r)))
            }
            
            return Disposer {
                guard cancelNonCompleted else { return }
                leftFuture.cancel()
                rightFuture.cancel()
            }
        }
    }
}

/// Returns a new future joining `a` and `b`. If both `a` and `b` succeed, the returned future will succeed with both's results. If either `a` or `b` fails, the returned future will fail as well.
/// - Parameter cancelNonCompleted: If true (default), as the returned future completes, `a` and `b` will be canceled if possible
public func join<A, B>(_ a: Future<A>, _ b: Future<B>, cancelNonCompleted: Bool = true) -> Future<(A, B)> {
    return a.join(with: b, cancelNonCompleted: cancelNonCompleted)
}

/// Returns a new future joining `a`, `b` and `c`. If `a`, `b` and `c` all succeed, the returned future will succeed with all three's results. If either `a`, `b` or `c` fails, the returned future will fail as well.
/// - Parameter cancelNonCompleted: If true (default), as the returned future completes, `a`, `b` and `b` will be canceled if possible
public func join<A, B, C>(_ a: Future<A>, _ b: Future<B>, _ c: Future<C>, cancelNonCompleted: Bool = true) -> Future<(A, B, C)> {
    return a.join(with: b, cancelNonCompleted: cancelNonCompleted).join(with: c, cancelNonCompleted: cancelNonCompleted).map { ($0.0, $0.1, $1) }
}

/// Returns a new future joining `futures`. Id all the futures in `futures` succeed, the returned future will succeed with the results from the futures. If any future in `futures` fail, the returned future will fail as well.
/// - Parameter cancelNonCompleted: If true (default), as the returned future completes, the futures in `futures` will be canceled if possible
public func join<T>(_ futures: [Future<T>], cancelNonCompleted: Bool = true) -> Future<[T]> {
    guard !futures.isEmpty else { return Future([]) }
    var results = [T?](repeating: nil, count: futures.count)
    let mutex = Mutex()
    func onValue(_ i: Int, _ val: T) {
        mutex.protect {
            results[i] = val
        }
    }
    
    var future = futures.first!.onValue(on: .none) { onValue(0, $0) }
    
    for (i, f) in futures.dropFirst().enumerated() {
        future = future.join(with: f, cancelNonCompleted: cancelNonCompleted).map(on: .none) { $0.1 }.onValue(on: .none) { onValue(i+1, $0) }
    }
    
    return future.map { _ in results.compactMap { $0 } }
}

public extension Future {
    /// Returns a new future selecting between `self` and `other`. When either `self` or `other` completes, the returned future completes with its result.
    /// - Parameter cancelNonCompleted: If true (default), as the returned future completes, `self` and `other` will be canceled if possible
    @discardableResult
    func select<T>(between other: Future<T>, cancelNonCompleted: Bool = true) -> Future<Either<Value, T>> {
        return Future<Either<Value, T>> { completion, mover in
            let leftFuture = mover.moveInside(self).onValue(on: .none) { completion(.success(Either.left($0))) }.onError(on: .none) { completion(.failure($0)) }
            let rightFuture = mover.moveInside(other).onValue(on: .none) { completion(.success((Either.right($0)))) }.onError(on: .none) { completion(.failure($0)) }
            
            return Disposer {
                guard cancelNonCompleted else { return }
                leftFuture.cancel()
                rightFuture.cancel()
            }
        }
    }
}

/// Returns a new future selecting between `left` and `right`. When either `left` or `right` completes, the returned future completes with its result.
/// - Parameter cancelNonCompleted: If true (default), as the returned future completes, `left` and `right` will be canceled if possible
@discardableResult
public func select<L, R>(_ left: Future<L>, or right: Future<R>, cancelNonCompleted: Bool = true) -> Future<Either<L, R>> {
    return left.select(between: right, cancelNonCompleted: cancelNonCompleted)
}

/// Returns a new future selecting between the futures in `futures`. When the first future in `futures` completes, the returned future completes with its result.
/// - Parameter cancelNonCompleted: If true (default), as the returned future completes, futures in `futures` will be canceled if possible
@discardableResult
public func select<T>(between futures: [Future<T>], cancelNonCompleted: Bool = true) -> Future<T> {
    precondition(!futures.isEmpty, "At least one future must be provided")
    
    var future = futures.first!
    for f in futures.dropFirst() {
        future = future.select(between: f, cancelNonCompleted: cancelNonCompleted).map(on: .none) {
            switch $0 {
            case let .right(val):
                return val
            case let .left(val):
                return val
            }
        }
    }
    
    return future
}

public extension Sequence {
    /// Returns a new future where `self`'s elements are transformed one at the time using `transform`.
    /// An element will not be transformed using `transform` until the previous elements future has completed.
    /// The returning future is the collection of the successfulr values from all the futures transformed by `transform`.
    /// If any future fails or `transform` throws, the returned future will fail as well, and no more elements will be transformed.
    @discardableResult
    func mapToFuture<T>(on scheduler: Scheduler = .current, _ transform: @escaping (Iterator.Element) throws -> Future<T>) -> Future<[T]> {
        var generator = makeIterator()
        guard let first = generator.next() else { return Future([]) }
        
        var result = [T]()
        
        var prevFuture = Future().flatMap(on: scheduler) { try transform(first) }
        while let next = generator.next() {
            prevFuture = prevFuture.flatMap(on: scheduler) { val in
                result.append(val)
                return try transform(next)
            }
        }
        
        return prevFuture.map(on: .none) { val -> [T] in
            result.append(val)
            return result;
        }
    }
    
    /// Returns a new future where `self`'s elements are transformed one at the time using `transform`.
    /// An element will not be transformed using `transform` until the previous elements future has completed.
    /// The returning future is the collection of the results from all the futures transformed by `transform`.
    /// If any future fails or `transform` throws, the error will be captured in the returned future's result array, and the returned future will still successfully complete.
    func mapToFutureResults<T>(on scheduler: Scheduler = .current, _ transform: @escaping (Iterator.Element) throws -> Future<T>) -> Future<[Result<T>]> {
        var generator = makeIterator()
        guard let first = generator.next() else { return Future([]) }
        
        var result = [Result<T>]()
        
        var prevFuture = Future().flatMap(on: scheduler) { try transform(first) }
        while let next = generator.next() {
            prevFuture = prevFuture.flatMapResult(on: scheduler) { val in
                result.append(val)
                return try transform(next)
            }
        }
        
        return prevFuture.flatMapResult(on: .none) { res -> Future<[Result<T>]> in
            result.append(res)
            return Future<[Result<T>]>(result)
        }
    }
}

public extension Future {
    /// The returned future completes when either `self` of any of the `futures` completes, whichever completes first.
    /// If any of the futures in `futures` completes first the returned future will always fail with either the future's error or `FutureError.aborted` if it completes successfully.
    func abort(forFutures futures: [Future<()>]) -> Future {
        return Future { completion in
            let future = self.onResult(on: .none, completion)
            
            let aborts = Flow.select(between: futures).onResult(on: .none) { r in
                completion(.failure(r.error ?? FutureError.aborted))
            }
            
            return Disposer {
                future.cancel()
                aborts.cancel()
            }
        }
    }
}

/// Helper type that will make sure overlapping performances is only performed once
public final class SingleTaskPerformer<Value> {
    private let mutex = Mutex()
    private var future: Future<Value>?? = nil
    
    public init() { }
    
    /// Returns a future that will complete with the result from the future returned from `function`.
    /// If a previous call to `performSingleTask` is still pending, `function` will not be called and instead the returned future will complete with the result from the pending future.
    @discardableResult
    public func performSingleTask(_ function: @escaping () -> Future<Value>) -> Future<Value> {
        mutex.lock()
        
        // Double unwrap
        if case let f?? = future {
            mutex.unlock()
            return f.onResult(on: .none) { _ in } // Add continuation to not let a cancel on one returned future cancel all returned futures.
        }
        
        future = .some(nil) // mark as calling out
        
        mutex.unlock() // unlock while calling out as we might either recurs or always might execute at once.
        let singleFuture = function().always(on: .none) {
            self.mutex.protect { self.future = nil }
        }
        mutex.lock()
        
        if case .some(nil) = future { // Not nil-ed while calling out?
            future = singleFuture
        }
    
        mutex.unlock()
        return singleFuture.onResult(on: .none) { _ in } // Add continuation to not let a cancel on one returned future cancel all returned futures.
    }
    
    public var isPerforming: Bool {
        return mutex.protect { self.future != nil }
    }
}

public extension SingleTaskPerformer where Value == () {
    /// If called several times only the first will be executed for the same run-loop.
    @discardableResult
    func coalesceToNextRunLoop(on scheduler: Scheduler = .current, action: @escaping () throws -> ()) -> Future<()> {
        return performSingleTask {
            Future().delay(by: 0).onValue(on: scheduler, action)
        }
    }
}
