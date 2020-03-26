//
//  FutureQueue.swift
//  Flow
//
//  Created by Måns Bernhardt on 2015-11-05.
//  Copyright © 2015 iZettle. All rights reserved.
//

import Foundation

/// A queue for futures.
///
/// Future queues are useful for handling exclusive access to a resource, and/or when it is important that independent operations are performed one after the other.
/// Enqueuing an asynchronous operation will delay its execution until the queue becomes empty.
public final class FutureQueue<Resource> {
    private let maxConcurrentCount: Int
    private var concurrentCount = 0
    private let queueScheduler: Scheduler
    private var _closedError: Error?
    private let isEmptyCallbacker = Callbacker<Bool>()
    private var _mutex = pthread_mutex_t()

    // enqueued items.
    private var items: [Executable] = [] {
        didSet {
            isEmptyCallbacker.callAll(with: isEmpty)
        }
    }

    /// The resource protected by this queue
    public let resource: Resource

    /// Creates a new queue instance.
    /// - Parameter resource: An instance of a resource for convenient access, typically a resource we want to ensure exlusive access to.
    /// - Parameter maxConcurrentCount: The max number of simultaniously performed operations, defaults to 1.
    /// - Parameter executeOn: An optional scheduler where the enqueue callback will be scheduled on.
    public init(resource: Resource, maxConcurrentCount: Int = 1, executeOn: Scheduler = .current) {
        precondition(maxConcurrentCount > 0, "maxConcurrentCount must 1 or greater")
        self.resource = resource
        self.maxConcurrentCount = maxConcurrentCount
        queueScheduler = executeOn
        OSAtomicIncrement32(&futureQueueUnitTestAliveCount)
        memPrint("Queue init", futureQueueUnitTestAliveCount)
    }

    deinit {
        OSAtomicDecrement32(&futureQueueUnitTestAliveCount)
        memPrint("Queue deinit", futureQueueUnitTestAliveCount)
    }
}

public extension FutureQueue {
    /// Enqueues an `operation` that will be executed when or once the queue becomes empty.
    /// - Returns: A future that will complete when the future returned from `operation` completes.
    @discardableResult
    func enqueue<Output>(_ operation: @escaping () throws -> Future<Output>) -> Future<Output> {
        if let error = closedError {
            return Future(error: error)
        }

        return Future { completion in
            let item = QueueItem<Output>(operation: operation, completion: completion)

            self.withMutex { $0.lock() }
            self.items.append(item)
            self.withMutex { $0.unlock() }

            self.executeNextItem()

            return Disposer(item.cancel)
        }
    }

    /// Enqueues an `operation` that will be executed when or once the queue becomes empty.
    /// - Returns: A future that will complete with the result from `operation`.
    @discardableResult
    func enqueue<Output>(_ operation: @escaping () throws -> Output) -> Future<Output> {
        return enqueue { return Future(try operation()) }
    }

    /// Enqueues an `operation` that will be executed with a new sub-queue when or once the queue becomes empty.
    ///
    /// Once the `operation` is ready to be executed it will be called with a new insance of `self` holding a copy of `self`'s resource.
    /// This sub-queue can be used to enqueue sub-operations and the `operation` enqueued on `self` will not complete until
    /// the sub-queue becomes empty and the retuned future from `operation` completes.
    ///
    /// - Returns: A future that will complete when the future returned from `operation` completes as well as the sub-queue becomes empty.
    @discardableResult
    func enqueueBatch<Output>(_ operation: @escaping (FutureQueue) throws -> Future<Output>) -> Future<Output> {
        let childQueue = FutureQueue(resource: resource, executeOn: queueScheduler)
        return enqueue {
            try operation(childQueue).flatMapResult { result in
                Future<Output> { completion in
                    childQueue.isEmptySignal.atOnce().filter { $0 }.onValue { _ in
                        completion(result)
                    }
                }
            }
        }.onError { error in
            childQueue.abortQueuedOperations(with: error, shouldCloseQueue: true)
        }.onCancel {
            childQueue.abortQueuedOperations(with: NSError(domain: "com.izettle.future.error", code: 1, userInfo: [ NSLocalizedDescriptionKey: "No more queueing allowed on closed child queue" ]), shouldCloseQueue: true)
        }
    }

    /// Enqueues an `operation` that will be executed with a new sub-queue when or once the queue becomes empty.
    ///
    /// Once the `operation` is ready to be executed it will be called with a new insance of `self` holding a copy of `self`'s resource.
    /// This sub-queue can be used to enqueue sub-operations and the `operation` enqueued on `self` will not complete until
    /// the sub-queue becomes empty.
    ///
    /// - Returns: A future that will complete with the result from `operation` once the sub-queue becomes empty.
    @discardableResult
    func enqueueBatch<Output>(_ operation: @escaping (FutureQueue) throws -> Output) -> Future<Output> {
        return enqueueBatch { return Future(try operation($0)) }
    }
}

public extension FutureQueue {
    /// Do we have any enqueued operations?
    var isEmpty: Bool {
        return withMutex { $0.protect { items.isEmpty } }
    }

    /// Returns a signal that will signal when `isEmpty` is changed.
    var isEmptySignal: ReadSignal<Bool> {
        return ReadSignal(getValue: { self.isEmpty }, callbacker: isEmptyCallbacker).distinct()
    }

    /// Returns a signal that will signal when the queue becomes empty
    var didBecomeEmpty: Signal<()> {
        return isEmptySignal.filter { $0 }.toVoid()
    }
}

public extension FutureQueue where Resource == () {
    /// Creates a new queue instance.
    /// - Parameter maxConcurrentCount: The max number of simultaniously performed operations, defaults to 1.
    /// - Parameter executeOn: An optional scheduler where the enqueue callback will be scheduled on.
    convenience init(maxConcurrentCount: Int = 1, executeOn: Scheduler = .current) {
        self.init(resource: (), maxConcurrentCount: maxConcurrentCount, executeOn: executeOn)
    }
}

public extension FutureQueue {
    /// Will abort all non completed enqueued futures and complete the future returned from enqueue with `error`.
    /// - Parameter error: The error to complete non yet completed futures returned from enqueue.
    /// - Parameter shouldCloseQueue: If true, all succeeding enqueued operations won't be executed and the
    ///   future returned from `enqueue()` will immediately abort with `error`. Defaults to false.
    func abortQueuedOperations(with error: Error, shouldCloseQueue: Bool = false) {
        lock()
        if shouldCloseQueue {
            _closedError = error
        }

        let items = self.items
        self.items = []
        unlock()

        for item in items {
            item.abort(with: error)
        }
    }

    /// The error passed to `abortQueuedExecutionWithError()` if called with `shouldCloseQueue` as true.
    var closedError: Error? {
        return withMutex { $0.protect { _closedError } }
    }
}

private extension FutureQueue {
    private func withMutex<T>(_ body: (PThreadMutex) throws -> T) rethrows -> T {
        try withUnsafeMutablePointer(to: &_mutex, body)
    }

    func lock() { withMutex { $0.lock() } }
    func unlock() { withMutex { $0.unlock() } }

    func removeItem(_ item: Executable) {
        withMutex { $0.lock() }
        _ = items.firstIndex { $0 === item }.map { items.remove(at: $0) }
        withMutex { $0.unlock() }
    }

    func executeNextItem() {
        lock()
        guard concurrentCount < maxConcurrentCount else { return unlock() }
        guard let item = items.filter({ !$0.isExecuting }).first else { return unlock() }

        concurrentCount += 1
        unlock()

        item.execute(on: queueScheduler) {
            self.lock()
            self.concurrentCount -= 1
            self.unlock()
            self.removeItem(item)
            self.executeNextItem()
        }
    }
}

var queueItemUnitTestAliveCount: Int32 = 0
var futureQueueUnitTestAliveCount: Int32 = 0

/// QueueItem is generic on Output but we can't hold a queue of heterogeneous items, hence this helper protocol
private protocol Executable: class {
    func execute(on scheduler: Scheduler, completion: @escaping () -> Void)
    var isExecuting: Bool { get }

    func abort(with error: Error)
    func cancel()
}

private final class QueueItem<Output>: Executable {
    private let operation: () throws -> Future<Output>
    private let completion: (Result<Output>) -> ()
    private weak var future: Future<Output>?
    private var hasBeenCancelled = false
    private var _mutex = pthread_mutex_t()
    private func withMutex<T>(_ body: (PThreadMutex) throws -> T) rethrows -> T {
        try withUnsafeMutablePointer(to: &_mutex, body)
    }

    init(operation: @escaping () throws -> Future<Output>, completion: @escaping (Result<Output>) -> ()) {
        self.completion = completion
        self.operation = operation
        withMutex { $0.initialize() }

        OSAtomicIncrement32(&queueItemUnitTestAliveCount)
        memPrint("Queue Item init", queueItemUnitTestAliveCount)
    }

    deinit {
        withMutex { $0.deinitialize() }
        OSAtomicDecrement32(&queueItemUnitTestAliveCount)
        memPrint("Queue Item deinit", queueItemUnitTestAliveCount)
    }

    private func lock() { withMutex { $0.lock() } }
    private func unlock() { withMutex { $0.unlock() } }

    private func complete(_ result: (Result<Output>)) {
        lock()
        let future = self.future
        unlock()
        future?.cancel()
        completion(result)
    }

    func execute(on scheduler: Scheduler, completion: @escaping () -> Void) {
        let future = Future().flatMap(on: scheduler, operation).onResult { result in
            self.complete(result)
        }.always(completion)

        lock()
        self.future = future
        if hasBeenCancelled {
            unlock()
            future.cancel()
        } else {
            unlock()
        }
    }

    func abort(with error: Error) {
        complete(.failure(error))
    }

    var isExecuting: Bool {
        lock()
        defer { unlock() }
        return future != nil
    }

    func cancel() {
        lock()
        hasBeenCancelled = true
        let future = self.future
        unlock()
        future?.cancel()
    }
}
