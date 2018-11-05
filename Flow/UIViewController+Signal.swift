//
//  UIViewController+Signals.swift
//  Flow
//
//  Created by João D. Moreira on 2018-11-02.
//  Copyright © 2018 iZettle. All rights reserved.
//

#if canImport(UIKit)

import UIKit

public extension UIViewController {
    var viewDidLoadSignal: Signal<Void> {
        return Signal(callbacker: callbackers.viewDidLoad)
    }

    var viewWillAppearSignal: Signal<Bool> {
        return Signal(callbacker: callbackers.viewWillAppear)
    }

    var viewDidAppearSignal: Signal<Bool> {
        return Signal(callbacker: callbackers.viewDidAppear)
    }

    var viewWillDisappearSignal: Signal<Bool> {
        return Signal(callbacker: callbackers.viewWillDisappear)
    }

    var viewDidDisappearSignal: Signal<Bool> {
        return Signal(callbacker: callbackers.viewDidDisappear)
    }

    var viewWillLayoutSubviewsSignal: Signal<Void> {
        return Signal(callbacker: callbackers.viewWillLayoutSubviews)
    }

    var viewDidLayoutSubviewsSignal: Signal<Void> {
        return Signal(callbacker: callbackers.viewDidLayoutSubviews)
    }
}

/// A callbacker box used by the swizzled implementations
private class Callbackers {
    let viewDidLoad = Callbacker<Void>()
    let viewWillAppear = Callbacker<Bool>()
    let viewDidAppear = Callbacker<Bool>()
    let viewWillDisappear = Callbacker<Bool>()
    let viewDidDisappear = Callbacker<Bool>()
    let viewWillLayoutSubviews = Callbacker<Void>()
    let viewDidLayoutSubviews = Callbacker<Void>()
}

private var callbackersKey = false
private extension UIViewController {
    var callbackers: Callbackers {
        let _ = UIViewController.runOnce

        if let previousValue = objc_getAssociatedObject(self, &callbackersKey) as? Callbackers {
            return previousValue
        } else {
            let initial = Callbackers()
            objc_setAssociatedObject(self, &callbackersKey, initial, .OBJC_ASSOCIATION_RETAIN)
            return initial
        }
    }
}

/// Swizzling of all UIViewController lifecycle methods
private extension UIViewController {
    static let runOnce: Void = {
        selectorsToSwizzle.forEach { (original, swizzled) in
            swizzle(class: UIViewController.self, original: original, swizzled: swizzled)
        }
    }()

    static let selectorsToSwizzle: [(original: Selector, swizzled: Selector)] = [
        (#selector(UIViewController.viewDidLoad), #selector(UIViewController._swizzled_viewDidLoad)),
        (#selector(UIViewController.viewWillAppear(_:)), #selector(UIViewController._swizzled_viewWillAppear(_:))),
        (#selector(UIViewController.viewDidAppear(_:)), #selector(UIViewController._swizzled_viewDidAppear(_:))),
        (#selector(UIViewController.viewWillDisappear(_:)), #selector(UIViewController._swizzled_viewWillDisappear(_:))),
        (#selector(UIViewController.viewDidDisappear(_:)), #selector(UIViewController._swizzled_viewDidDisappear(_:))),
        (#selector(UIViewController.viewWillLayoutSubviews), #selector(UIViewController._swizzled_viewWillLayoutSubviews)),
        (#selector(UIViewController.viewDidLayoutSubviews), #selector(UIViewController._swizzled_viewDidLayoutSubviews)) ]
}

private func swizzle(class aClass: AnyClass, original: Selector, swizzled: Selector) {
    guard let original = class_getInstanceMethod(aClass, original),
        let swizzled = class_getInstanceMethod(aClass, swizzled) else {
            assertionFailure("Invalid selector for " +  String(describing: aClass))
            return
    }

    method_exchangeImplementations(original, swizzled)
}

/// Swizzled method implementations
private extension UIViewController {
    @objc func _swizzled_viewDidLoad() {
        self._swizzled_viewDidLoad()
        callbackers.viewDidLoad.callAll()
    }

    @objc func _swizzled_viewWillAppear(_ animated: Bool) {
        self._swizzled_viewWillAppear(animated)
        callbackers.viewWillAppear.callAll(with: animated)
    }

    @objc func _swizzled_viewDidAppear(_ animated: Bool) {
        self._swizzled_viewDidAppear(animated)
        callbackers.viewDidAppear.callAll(with: animated)
    }

    @objc func _swizzled_viewWillDisappear(_ animated: Bool) {
        self._swizzled_viewWillDisappear(animated)
        callbackers.viewWillDisappear.callAll(with: animated)
    }

    @objc func _swizzled_viewDidDisappear(_ animated: Bool) {
        self._swizzled_viewDidDisappear(animated)
        callbackers.viewDidDisappear.callAll(with: animated)
    }

    @objc func _swizzled_viewWillLayoutSubviews() {
        self._swizzled_viewWillLayoutSubviews()
        callbackers.viewWillLayoutSubviews.callAll()
    }

    @objc func _swizzled_viewDidLayoutSubviews() {
        self._swizzled_viewDidLayoutSubviews()
        callbackers.viewDidLayoutSubviews.callAll()
    }
}

#endif
