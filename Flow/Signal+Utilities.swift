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
