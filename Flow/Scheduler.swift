//
//  Scheduler.swift
//  Flow
//
//  Created by Måns Bernhardt on 2015-09-30.
//  Copyright © 2015 iZettle. All rights reserved.
//

import Foundation


/// Encapsulates how to asynchronously and synchronously scheduler work and allows comparing if two instances are representing the same scheduler.
public final class Scheduler {
    private let identifyingObject: AnyObject
    private let _async: (@escaping () -> Void) -> Void
    private let _sync: (() -> Void) -> Void

    /// Creates an instance that will use `async` for asynchrouns scheduling and `sync` for synchrouns scheduling.
    /// - Parameter identifyingObject: Used to identify if two scheduler are the same using `===`.
    public init(identifyingObject: AnyObject, async: @escaping (@escaping () -> Void) -> Void, sync: @escaping (() -> Void) -> Void) {
        self.identifyingObject = identifyingObject
        _async = async
        _sync = sync
    }
}

public extension Scheduler {
    /// Asynchronously schedules `work` unless we are already currently scheduling work on `self`, where the `work` be immediately called.
    func async(execute work: @escaping () -> Void) {
        guard !isImmediate else {
            return work()
        }

        _async {
            let state = threadState
            assert(state.scheduler == nil)
            state.scheduler = self
            work()
            state.scheduler = nil
        }
    }

    /// Synchronously schedules `work` unless we are already currently scheduling work on `self`, where the `work` be immediately called.
    func sync<T>(execute work: () -> T) -> T {
        guard !isImmediate else {
            return work()
        }
        
        let state = threadState
        state.syncScheduler = self
        var result: T!
        _sync  {
            result = work()
        }
        state.syncScheduler = nil
        return result
    }
    
    /// Returns true if `async()` and `sync()` will execute work immediately and hence not be scheduled.
    var isImmediate: Bool {
        if (self == .main && Thread.isMainThread) || self == .none { return true }
        let state = threadState
        return self == state.scheduler || self == state.syncScheduler
    }
    
    /// Returns true if `self` is currently execute work
    var isExecuting: Bool {
        let state = threadState
        return self == state.scheduler  || (Thread.isMainThread && self == .main) || self == state.syncScheduler
    }
    
    /// Synchronously schedules `work` unless we are already currently scheduling work on `self`, where the `work` be immediately called.
    /// - Throws: If `work` throws.
    func sync<T>(execute work: () throws -> T) throws -> T {
        return try sync {
            Result { try work() }
        }.getValue()
    }
    
    /// Will asynchronously schedule `work` on `self` after `delay` seconds
    func async(after delay: TimeInterval, execute work: @escaping () -> ()) {
        return DispatchQueue.concurrentBackground.asyncAfter(deadline: DispatchTime.now() + delay) {
            self.async(execute: work)
        }
    }
}

public extension Scheduler {
    /// The scheduler we are currently being scheduled on.
    /// If we are currently not being scheduled, `.main` will be returned if we are on the main thread or `.background` if not.
    static var current: Scheduler {
        let state = threadState
        return state.syncScheduler ?? state.scheduler ?? (Thread.isMainThread ? .main : .background)
    }

    /// A Scheduler that won't schedule any work and hence just call work() immediatly
    static let none = Scheduler(identifyingObject: 0 as AnyObject, async: { _ in fatalError() }, sync: { _ in fatalError() })

    /// A Scheduler that will schedule work on `DispatchQueue.main``
    static let main = Scheduler(queue: .main)

    /// A Scheduler that will schedule work on a serial background queue
    static let background = Scheduler(label: "flow.background.serial")

    /// A Scheduler that will schedule work on a concurrent background queue
    static let concurrentBackground = Scheduler(label: "flow.background.concurrent", attributes: .concurrent)
}

public extension Scheduler {
    /// Create a new instance that will schedule its work on the provided `queue`
    convenience init(queue: DispatchQueue) {
        self.init(identifyingObject: queue, async: { queue.async(execute: $0) }, sync: queue.sync)
    }

    /// Create a new instance that will schedule its work on a `DispatchQueue` created with the the provided `label` and `attributes`.
    public convenience init(label: String, attributes: DispatchQueue.Attributes = []) {
        self.init(queue: DispatchQueue(label: label, attributes: attributes))
    }
}

extension Scheduler: Equatable {
    public static func ==(lhs: Scheduler, rhs: Scheduler) -> Bool {
        return lhs.identifyingObject === rhs.identifyingObject
    }
}

// Below breaks fastlane builds
//#if canImport(CoreData)
//import CoreData
//
//pubic extension NSManagedObjectContext {
//    var scheduler: Scheduler {
//        return concurrencyType == .mainQueueConcurrencyType ? .main : Scheduler(identifyingObject: self, async: perform, sync: performAndWait)
//    }
//}
//#endif


/// Used for scheduling delays and might be overridend in unit test with simulatated delays
func disposableAsync(after delay: TimeInterval, execute work: @escaping () -> ()) -> Disposable {
    return _disposableAsync(delay, work)
}

private var _disposableAsync: (_ delay: TimeInterval, _ work: @escaping () -> ()) -> Disposable = Scheduler.concurrentBackground.disposableAsync

/// Useful for overriding `disposableAsync` in unit test with simulatated delays
func overrideDisposableAsync(by disposableAsync: @escaping (_ delay: TimeInterval, _ work: @escaping () -> ()) -> Disposable) -> Disposable {
    let prev = _disposableAsync
    _disposableAsync = disposableAsync
    return Disposer {
        _disposableAsync = prev
    }
}

extension Scheduler {
    /// Will asynchronously schedule `work` on `self` after `delay` seconds
    /// - Returns: A disposable for cancelation
    /// - Note: There is no guarantee that `work` will not be called after disposing the returned `Disposable`
    func disposableAsync(after delay: TimeInterval, execute work: @escaping () -> ()) -> Disposable {
        precondition(delay >= 0)
        let s = StateAndCallback(state: Optional(work))

        async(after: delay) { [weak s] in
            guard let s = s else { return }
            s.lock()
            let work = s.val
            s.val = nil
            s.unlock()

            // We can not hold a lock while calling out (risk of deadlock if callout calls dispose), hence dispose might be called just after releasing a lock but before calling out. This means there is guarantee `work` would be called after a dispose.
            work?()
        }
        
        return Disposer { s.protectedVal = nil }
    }
}

extension DispatchQueue {
    static let concurrentBackground = DispatchQueue(label: "flow.background.concurrent", attributes: .concurrent)
    static let serialBackground = DispatchQueue(label: "flow.background.serial")
}


final class ThreadState {
    var scheduler: Scheduler?
    var syncScheduler: Scheduler?
    init() {}
}

var threadState: ThreadState {
    guard !Thread.isMainThread else { return mainThreadState }
    if let p = pthread_getspecific(threadStateKey) {
        return Unmanaged<ThreadState>.fromOpaque(p).takeUnretainedValue()
    }
    let s = ThreadState()
    pthread_setspecific(threadStateKey, Unmanaged.passRetained(s).toOpaque())
    return s
}

private let mainThreadState = ThreadState()
private var _threadStateKey: pthread_key_t = 0
private var threadStateKey: pthread_key_t = {
    pthread_key_create(&_threadStateKey, nil)
    return _threadStateKey
}()

