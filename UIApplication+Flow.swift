//
//  UIApplication+Flow.swift
//  Flow
//
//  Created by Carl Ekman on 2018-10-03.
//  Copyright © 2018 iZettle. All rights reserved.
//

import UIKit

public extension UIApplication {
    /// The `UIApplication` callback events that signify a state change.
    enum StateChangeCallback {
        case willEnterForeground, willResignActive, didBecomeActive, didEnterBackground
    }

    /// A signal containing the new `UIApplicationState` whenever it is about to (or did) change.
    var appStateSignal: Signal<UIApplicationState> {
        return signal(for: .willEnterForeground, .willResignActive, .didBecomeActive, .didEnterBackground)
            .map { ($0.object as? UIApplication)?.applicationState ?? .active }
            .distinct()
    }

    /// The notification signal for a given `StateChangeCallback`.
    func signal(for appStateCallbacks: StateChangeCallback...) -> Signal<(Notification)> {
        var signals = [Signal<(Notification)>]()
        for callback in appStateCallbacks {
            let signal = NotificationCenter.default.signal(forName: callback.notificationName)
            signals.append(signal)
        }
        return merge(signals)
    }
}

private extension UIApplication.StateChangeCallback {
    /// The related notification name.
    var notificationName: NSNotification.Name {
        switch self {
        case .willEnterForeground:
            return .UIApplicationWillEnterForeground
        case .willResignActive:
            return .UIApplicationWillResignActive
        case .didBecomeActive:
            return .UIApplicationDidBecomeActive
        case .didEnterBackground:
            return .UIApplicationDidEnterBackground
        }
    }
}
