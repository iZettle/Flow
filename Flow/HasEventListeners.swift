//
//  HasEventListeners.swift
//  Flow
//
//  Created by Måns Bernhardt on 2015-11-27.
//  Copyright © 2015 PayPal Inc. All rights reserved.
//

import Foundation

/// Whether the conforming class has event listeners.
public protocol HasEventListeners: class {
    /// Boolean value indicating whether the instance currently has event listeners.
    var hasEventListeners: Bool { get }
}

/// Whether the conforming type can provide an array of all sub views/items that conform to `Enablable & HasEventListeners`.
public protocol HasEnablableEventListeners {
    // An array of all sub views/items that conform to `Enablable & HasEventListeners`
    var enablableEventListeners: [Enablable & HasEventListeners] { get }
}

public extension HasEnablableEventListeners {
    /// Will find and disable all sub views/items that conform `Enablable & HasEventListeners` that currently has event listeners.
    /// - Returns: A `Disposable` that will upon dispose re-enable the views/items being disabled.
    func disableActiveEventListeners() -> Disposable {
        let activeListeners = enablableEventListeners.filter { $0.hasEventListeners }.filter { ($0 as Enablable).isEnabled }
        return DisposeBag(activeListeners.map { $0.disable() })
    }
}

#if canImport(UIKit)

import UIKit

extension UIView: HasEnablableEventListeners {
    public var enablableEventListeners: [Enablable & HasEventListeners] {
        return allDescendants(ofType: (Enablable & HasEventListeners).self)
    }
}

extension UINavigationItem: HasEnablableEventListeners {
    public var enablableEventListeners: [Enablable & HasEventListeners] {
        return allItemsAndDecendants(ofType: (Enablable & HasEventListeners).self)
    }
}

extension UIViewController: HasEnablableEventListeners {
    public var enablableEventListeners: [Enablable & HasEventListeners] {
        return view.enablableEventListeners + navigationItem.enablableEventListeners
    }
}

private extension UINavigationItem {
    func allItemsAndDecendants<T>(ofType type: T.Type) -> [T] {
        var result = [T]()
        let items = (leftBarButtonItems ?? []) + (rightBarButtonItems ?? [])
        result += items.compactMap { $0 as? T }
        result += items.compactMap { $0.customView }.flatMap { $0.allDescendants(ofType: T.self) }
        return result
    }
}

internal extension UIView {
    var allDescendants: [UIView] {
        return subviews + subviews.flatMap {
            $0.allDescendants
        }
    }

    func allDescendants<T>(ofType type: T.Type) -> [T] {
        return allDescendants.compactMap { $0 as? T }
    }
}

#endif
