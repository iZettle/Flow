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

        return CoreSignal(setValue: signal.setter, onEventType: { c in
            let bag = DisposeBag()
            bag += signal.onEventType { eventType in
                if case .initial = eventType { // Don't delay initial
                    c(eventType)
                } else {
                    bag += disposableAsync(after: delay) {
                        c(eventType)
                    }
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
        self.init { c in
            let bag = DisposeBag()
            guard interval.isFinite else { return bag }
            
            let timer = DispatchSource.makeTimerSource(queue: .concurrentBackground)
            
            bag += { _ = timer } // DispatchSourceTimer is automatically cancelled after being released
            timer.setEventHandler {
                c(())
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
        }
    }
    
    /// Creates a new signal that will signal once after `delay` seconds. Shorter version of `Signal(just: ()).delay(by: ...)`
    convenience init(after delay: TimeInterval) {
        self.init { c in
            return disposableAsync(after: delay) {
                c(())
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
    private var disposable: Disposable? = nil
    private var _mutex = pthread_mutex_t()
    private var mutex: PThreadMutex { return PThreadMutex(&_mutex) }
    private let scheduler: Scheduler
    private var callback: ((EventType<Value>) -> Void)?
    
    init(on scheduler: Scheduler, callback: @escaping (EventType<Value>) -> Void, onEventType: @escaping (@escaping (EventType<Value>) -> Void) -> Disposable) {
        self.scheduler = scheduler
        self.callback = callback
        mutex.initialize()
        
        let d = onEventType(handleEventType)
        
        mutex.lock()
        if self.callback == nil {
            d.dispose()
        } else {
            disposable = d
        }
        mutex.unlock()
    }
    
    deinit {
        dispose()
        mutex.deinitialize()
    }
    
    public func dispose() {
        mutex.lock()
        let d = disposable
        disposable = nil
        callback = nil
        mutex.unlock()
        d?.dispose()
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
            scheduler.async {
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

