//
//  UIViewController+Flow.swift
//  Flow
//
//  Created by Carl Ekman on 2018-10-02.
//  Copyright © 2018 iZettle. All rights reserved.
//

import UIKit

public class FlowViewController: UIViewController {
    private var viewDidLoadSignal = WriteSignal<()>()

    private var viewWillAppearSignal = WriteSignal<Bool>()
    private var viewDidAppearSignal = WriteSignal<Bool>()

    private var viewWillDisappearSignal = WriteSignal<Bool>()
    private var viewDidDisappearSignal = WriteSignal<Bool>()

    private var viewWillLayoutSubviewsSignal = WriteSignal<()>()
    private var viewDidLayoutSubviewsSignal = WriteSignal<()>()

    private var didReceiveMemoryWarningSignal = WriteSignal<()>()
    private var stateSignal = WriteSignal<UIApplicationState>()
}

extension FlowViewController {
    override public func viewDidLoad() {
        super.viewDidLoad()
        viewDidLoadSignal.emit()
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewWillAppearSignal.emit(animated)
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewDidAppearSignal.emit(animated)
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        viewWillDisappearSignal.emit(animated)
    }

    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        viewDidDisappearSignal.emit(animated)
    }

    override public func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        viewWillLayoutSubviewsSignal.emit()
    }

    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        viewDidLayoutSubviewsSignal.emit()
    }

    override public func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        didReceiveMemoryWarningSignal.emit()
    }
}

extension FlowViewController {
    public var didLoad: Signal<()> {
        return viewDidLoadSignal.plain()
    }

    public var willAppear: Signal<Bool> {
        return viewWillAppearSignal.plain()
    }

    public var didAppear: Signal<Bool> {
        return viewDidAppearSignal.plain()
    }

    public var willDisappear: Signal<Bool> {
        return viewWillDisappearSignal.plain()
    }

    public var didDisappear: Signal<Bool> {
        return viewDidDisappearSignal.plain()
    }

    public var willLayoutSubviews: Signal<()> {
        return viewWillLayoutSubviewsSignal.plain()
    }

    public var didLayoutSubviews: Signal<()> {
        return viewDidLayoutSubviewsSignal.plain()
    }

    public var receivedMemoryWarning: Signal<()> {
        return didReceiveMemoryWarningSignal.plain()
    }
}

extension FlowViewController {
    /// The current `UIApplicationState`, as observed through `NotificationCenter`.
    /// Will only emit values if `observeAppStateChanges()` has been called.
    public var appStateSignal: Signal<UIApplicationState> {
        return stateSignal.plain().distinct()
    }

    /// Call this to begin observing NSApplicationState updates, emitted to `appStateSignal`.
    public func observeAppStateChanges() -> Disposable {
        let app = UIApplication.shared
        let center = NotificationCenter.default
        let selector = #selector(FlowViewController.updateApplicationState(notification:))

        let willEnterForeground = NSNotification.Name.UIApplicationWillEnterForeground
        let willResignActive = NSNotification.Name.UIApplicationWillResignActive
        let didBecomeActive = NSNotification.Name.UIApplicationDidBecomeActive
        let didEnterBackground = NSNotification.Name.UIApplicationDidEnterBackground

        center.addObserver(self, selector: selector, name: willEnterForeground, object: app)
        center.addObserver(self, selector: selector, name: willResignActive, object: app)
        center.addObserver(self, selector: selector, name: didBecomeActive, object: app)
        center.addObserver(self, selector: selector, name: didEnterBackground, object: app)

        let bag = DisposeBag()
        bag += { center.removeObserver(self) }
        return bag
    }

    /// Internal callback for the observers.
    @objc private func updateApplicationState(notification: NSNotification) {
        let state = (notification.object as? UIApplication)?.applicationState ?? .active
        stateSignal.emit(state)
    }
}
