//
//  UIViewController+Flow.swift
//  Flow
//
//  Created by Carl Ekman on 2018-10-02.
//  Copyright © 2018 iZettle. All rights reserved.
//

import UIKit

public final class FlowViewController: UIViewController {
    public let lifecycleCallbacks = LifecycleCallbacks()
}

extension FlowViewController {
    override public func viewDidLoad() {
        super.viewDidLoad()
        lifecycleCallbacks.call(.didLoad)
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        lifecycleCallbacks.call(.willAppear)
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        lifecycleCallbacks.call(.didAppear)
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        lifecycleCallbacks.call(.willDisappear)
    }

    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        lifecycleCallbacks.call(.didDisappear)
    }

    override public func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        lifecycleCallbacks.call(.willLayoutSubviews)
    }

    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        lifecycleCallbacks.call(.didLayoutSubviews)
    }

    override public func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        lifecycleCallbacks.call(.didReceiveMemoryWarning)
    }
}

public extension UIViewController {
    struct LifecycleCallbacks {
        public enum LifecycleCallback: CaseIterable {
            case didLoad, willAppear, didAppear, willDisappear, didDisappear, willLayoutSubviews, didLayoutSubviews, didReceiveMemoryWarning
        }
        private let callbackers: [LifecycleCallback: Callbacker<()>]
        private let signals: [LifecycleCallback: Signal<()>]
    }
}

public extension UIViewController.LifecycleCallbacks {
    init() {
        var callbackers: [LifecycleCallback: Callbacker<()>] = [:]
        var signals: [LifecycleCallback: Signal<()>] = [:]
        for callback in LifecycleCallback.allCases {
            let callbacker = Callbacker<()>()
            callbackers[callback] = callbacker
            signals[callback] = Signal(callbacker: callbacker)
        }
        self.callbackers = callbackers
        self.signals = signals
    }

    subscript(callback: LifecycleCallback) -> Signal<()> {
        guard let signal = signals[callback] else {
            fatalError("Missing a signal for callback: \(callback)")
        }
        return signal
    }
}

private extension UIViewController.LifecycleCallbacks {
    func call(_ callback: LifecycleCallback) {
        guard let callbacker = callbackers[callback] else {
            fatalError("Missing a callbacker for callback: \(callback)")
        }
        callbacker.callAll(with: ())
    }
}
