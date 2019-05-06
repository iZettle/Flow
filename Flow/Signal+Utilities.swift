//
//  Signal+Utilities.swift
//  Flow
//
//  Created by Måns Bernhardt on 2016-03-11.
//  Copyright © 2016 iZettle. All rights reserved.
//

import Foundation

public extension NotificationCenter {
    /// Returns a signal for notifications named `name`.
    func signal(forName name: Notification.Name?, object: Any? = nil) -> Signal<Notification> {
        return Signal { callback in
            let observer = self.addObserver(forName: name, object: object, queue: nil, using: callback)
            return Disposer {
                self.removeObserver(observer)
            }
        }
    }
}

public extension Sequence {
    /// Returns a signal that will immedialty signals all `self`'s elements and then terminate.
    func signal() -> FiniteSignal<Iterator.Element> {
        return FiniteSignal(onEventType: { callback in
            callback(.initial(nil))
            self.forEach { callback(.event(.value($0))) }
            callback(.event(.end))
            return NilDisposer()
        })
    }
}

/// Returns signal that will signal once `object` is deallocated.
public func deallocSignal(for object: AnyObject) -> Signal<()> {
    let tracker = objc_getAssociatedObject(object, &trackerKey) as? DeallocTracker ?? DeallocTracker()
    objc_setAssociatedObject(object, &trackerKey, tracker, .OBJC_ASSOCIATION_RETAIN)
    return tracker.callbacker.providedSignal
}

public extension NSObject {
    /// Returns signal that will signal once `self` is deallocated.
    var deallocSignal: Signal<()> {
        return Flow.deallocSignal(for: self)
    }
}

private final class DeallocTracker {
    let callbacker = Callbacker<()>()
    deinit { callbacker.callAll(with: ()) }
}

private var trackerKey = false
