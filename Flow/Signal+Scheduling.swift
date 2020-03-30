//
//  Signal+Scheduling.swift
//  Flow
//
//  Created by Måns Bernhardt on 2017-12-12.
//  Copyright © 2017 iZettle. All rights reserved.
//

import Foundation

public extension SignalProvider {
    /// Returns a new signal delaying events by `delay`.
    /// - Parameter delay: The time to delay the signaled events. A delay of zero will still delay signaled events. However, passing a nil value will not delay signaled events.
    func delay(by delay: TimeInterval? = nil) -> CoreSignal<Kind, Value> {
        let signal = providedSignal

        guard let delay = delay else { return signal }
        precondition(delay >= 0)

        return CoreSignal(setValue: signal.setter, onEventType: { callback in
            let bag = DisposeBag()
            bag += signal.onEventType { eventType in
                if case .initial = eventType { // Don't delay initial
                    callback(eventType)
                } else {
                    bag += disposableAsync(after: delay) {
                        callback(eventType)
                    }
                }
            }
            return bag
        })
    }

    /// Returns a new signal delaying events by the result of executing the `delay` closure with the value.
    /// - Parameter delay: A closure that returns a time to delay the signaled events. A returned delay of zero will still delay signaled events. However, returning nil will not delay signaled events.
    func delay(on scheduler: Scheduler = .current, by delay: @escaping (Value) -> TimeInterval?) -> CoreSignal<Kind, Value> {
        let signal = providedSignal

        return CoreSignal(setValue: signal.setter, onEventType: { callback in
            let bag = DisposeBag()
            bag += signal.onEventType { eventType in
                switch eventType {
                case .initial: // Don't delay initial
                    callback(eventType)
                case .event(.value(let value)):
                    scheduler.async {
                        guard let delay = delay(value) else {
                            callback(eventType)
                            return
                        }

                        precondition(delay >= 0)

                        bag += disposableAsync(after: delay) {
                            callback(eventType)
                        }
                    }
                case .event(.end): // Don't delay initial
                    callback(eventType)
                }
            }
            return bag
        })
    }
}

public extension CoreSignal where Kind == Plain, Value == () {
    /// Creates a new signal that will signal once every `interval` seconds.
    /// - Parameter interval: The time between signaled events.
    /// - Parameter delay: If provided will delay the first event by `delay`. If nil (default), `interval` will be used as the delay.
    convenience init(every interval: TimeInterval, delay: TimeInterval? = nil) {
        precondition(interval >= 0)
        self.init(onValue: { callback in
            let bag = DisposeBag()
            guard interval.isFinite else { return bag }

            let timer = DispatchSource.makeTimerSource(queue: .concurrentBackground)

            bag.hold(timer) // DispatchSourceTimer is automatically cancelled after being released
            timer.setEventHandler {
                callback(())
            }

            let deadline: DispatchTime
            if let delay = delay {
                deadline = DispatchTime.now() + delay
            } else {
                deadline = DispatchTime.now() + interval
            }

            timer.schedule(deadline: deadline, repeating: interval)
            timer.resume()

            return bag
        })
    }

    /// Creates a new signal that will signal once after `delay` seconds. Shorter version of `Signal(just: ()).delay(by: ...)`
    convenience init(after delay: TimeInterval) {
        self.init { callback in
            return disposableAsync(after: delay) {
                callback(())
            }
        }
    }
}

internal extension CoreSignal {
    func onEventType(on scheduler: Scheduler, _ callback: @escaping (EventType) -> Void) -> Disposable {
        if scheduler == .none {
            return onEventType(callback)
        } else {
            return OnEventTypeDisposer(on: scheduler, callback: callback, onEventType: onEventType)
        }
    }
}

// Using custom Disposable instead of DisposeBag for efficiency (less allocations)
private final class OnEventTypeDisposer<Value>: Disposable {
    private var disposable: Disposable?
    private var mutex = pthread_mutex_t()

    private let scheduler: Scheduler
    private var callback: ((EventType<Value>) -> Void)?

    init(on scheduler: Scheduler, callback: @escaping (EventType<Value>) -> Void, onEventType: @escaping (@escaping (EventType<Value>) -> Void) -> Disposable) {
        self.scheduler = scheduler
        self.callback = callback
        mutex.initialize()

        let disposable = onEventType { [weak self] in self?.handleEventType($0) }

        mutex.lock()
        if self.callback == nil {
            disposable.dispose()
        } else {
            self.disposable = disposable
        }
        mutex.unlock()
    }

    deinit {
        dispose()
        mutex.deinitialize()
    }

    public func dispose() {
        mutex.lock()
        let disposable = self.disposable
        self.disposable = nil
        callback = nil
        mutex.unlock()
        disposable?.dispose()
    }

    func handleEventType(_ eventType: EventType<Value>) {
        mutex.lock()

        guard let callback = self.callback else {
            return mutex.unlock()
        }

        mutex.unlock()

        if scheduler.isImmediate {
            validate(eventType: eventType)
            callback(eventType)
            if case .event(.end) = eventType {
                dispose()
            }
        } else if case .initial = eventType { // initial is used for atOnce() and .value and needs to be immediate and can't hence be scheduled.
            validate(eventType: eventType)
            callback(eventType)
        } else {
            scheduler.async { [weak self] in
                guard let `self` = self else { return }
                // At the time we are scheduled, we might already been disposed
                self.mutex.lock()
                guard let callback = self.callback else {
                    return self.mutex.unlock()
                }

                self.validate(eventType: eventType)

                self.mutex.unlock()
                callback(eventType)
                if case .event(.end) = eventType {
                    self.dispose()
                }
            }
        }
    }

    #if DEBUG
    private var hasReceivedInitial = false
    func validate(eventType: EventType<Value>) {
        switch eventType {
        case .initial:
            assert(!hasReceivedInitial, "There should only be one .initial event")
            hasReceivedInitial = true
        case .event(.value):
            assert(hasReceivedInitial, "The .initial event must sent before any value event")
            assert(callback != nil, "No value events should be sent after an .end event")
        case .event(.end):
            assert(callback != nil, "Only one .end should be sent")
            assert(hasReceivedInitial, "The .initial event must sent before any end event")
        }
    }
    #else
    func validate(eventType: EventType<Value>) { }
    #endif
}
