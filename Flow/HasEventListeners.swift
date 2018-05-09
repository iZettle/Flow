//
//  HasEventListeners.swift
//  Flow
//
//  Created by Måns Bernhardt on 2015-11-27.
//  Copyright © 2015 iZettle. All rights reserved.
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
        activeListeners.forEach { $0.isEnabled = false }
        return Disposer {
            activeListeners.filter { $0.hasEventListeners }.forEach { $0.isEnabled = true }
        }
    }
}

#if canImport(UIKit)

import UIKit

extension UIView: HasEnablableEventListeners {
    public var enablableEventListeners: [Enablable & HasEventListeners] {
        return allSubviews(ofType: (Enablable & HasEventListeners).self)
    }
}

extension UINavigationItem: HasEnablableEventListeners {
    public var enablableEventListeners: [Enablable & HasEventListeners] {
        return allItemsOrViews(ofType: (Enablable & HasEventListeners).self)
    }
}

extension UIViewController: HasEnablableEventListeners {
    public var enablableEventListeners: [Enablable & HasEventListeners] {
        return view.enablableEventListeners + navigationItem.enablableEventListeners
    }
}

private extension UINavigationItem {
    func allItemsOrViews<T>(ofType type: T.Type) -> [T] {
        var result = [T]()
        let items = (leftBarButtonItems ?? []) + (rightBarButtonItems ?? [])
        result += items.compactMap { $0 as? T }
        result += items.compactMap { $0.customView }.flatMap { $0.allSubviews(ofType: T.self) }
        return result
    }
}

internal extension UIView {
    var allSubviews: [UIView] {
        return subviews + subviews.flatMap {
            $0.allSubviews
        }
    }
    
    func allSubviews<T>(ofType type: T.Type) -> [T] {
        return allSubviews.compactMap { $0 as? T }
    }
}

#endif


