//
//  UIControl+Extensions.swift
//  Flow
//
//  Created by Måns Bernhardt on 2015-09-17.
//  Copyright © 2015 iZettle. All rights reserved.
//


#if canImport(UIKit)

import UIKit

    
public extension UIControl {
    /// Returns a signal that will signal when any event in `controlEvents` is signaled on `self`.
    ///
    ///     bag += textField.signal(for: .editingDidBegin).onValue { ... }
    func signal(for controlEvents: UIControlEvents) -> Signal<()> {
        return Signal { c in
            let targetAction = TargetAction()
            self.addTarget(targetAction, action: TargetAction.selector, for: controlEvents)
            
            self.updateAutomaticEnabling()
            
            let bag = DisposeBag()
            bag += targetAction.addCallback(c)
            bag += Disposer {
                self.removeTarget(targetAction, action: TargetAction.selector, for: controlEvents)
                self.updateAutomaticEnabling()
            }
            return bag
        }
    }
}
    
extension UIControl: HasEventListeners, AutoEnablable {
    public var hasEventListeners: Bool {
        return !allTargets.filter { $0 is TargetAction }.isEmpty
    }
}
    
extension UIAlertAction: Enablable {}
    
extension UIControl: Enablable {}

extension UITextField : SignalProvider {
    public var providedSignal: ReadWriteSignal<String> {
        return signal(for: .editingChanged, keyPath: \.text)[\.[fallback: ""]]
    }
}

extension UIButton: SignalProvider {
    public var providedSignal: Signal<()> {
        return signal(for: .touchUpInside)
    }
}

extension UISwitch: SignalProvider {
    public var providedSignal: ReadWriteSignal<Bool> {
        return signal(for: .valueChanged, keyPath: \.isOn)
    }
}
    
extension UISegmentedControl: SignalProvider {
    public var providedSignal: ReadWriteSignal<Int> {
        return signal(for: .valueChanged, keyPath: \.selectedSegmentIndex)
            .distinct() // KVO seems to trigger when tapping as well, even when tapping selected.
    }
}

extension UIRefreshControl: SignalProvider {
    public var providedSignal: Signal<()> {
        return signal(for: .valueChanged)
    }
}
    
extension UIPasteboard: SignalProvider {
    public var providedSignal: ReadWriteSignal<String?> {
        return signal(for: \.string)
    }
}

extension UIDatePicker: SignalProvider {
    public var providedSignal: ReadWriteSignal<Date> {
        return signal(for: .valueChanged, keyPath: \.date)
    }
}

extension UIPageControl: SignalProvider {
    public var providedSignal: ReadWriteSignal<Int> {
        return signal(for: .valueChanged, keyPath: \.currentPage)
    }
}

extension UIBarItem: Enablable {}

extension UIBarButtonItem: TargetActionable, SignalProvider, HasEventListeners, AutoEnablable { }
    
public extension UIBarButtonItem {
    /// Creates a new instance using `button` as its custom view and where button `.touchUpInside` are forwarded to `self`.
    convenience init(button: UIButton) {
        self.init(customView: button)
        setupEvent(forSubControl: button)
    }
    
    /// Setup to forward `control`'s `.touchUpInside` events to `self`.
    /// Useful if you want want a customView or a subview of thereof, to trigger events for this bar item.
    func setupEvent(forSubControl control: UIControl) {
        control.addTarget(self, action: #selector(UIBarButtonItem.__barSubButton), for: .touchUpInside)
    }

    @objc private func __barSubButton() {
        _ = self.target?.perform(self.action)
    }
}

extension UIGestureRecognizer: SignalProvider {
    public var providedSignal: ReadSignal<UIGestureRecognizerState> {
        return Signal { callback in
            let targetAction = TargetAction()
            self.addTarget(targetAction, action: TargetAction.selector)
            let bag = DisposeBag()
            bag += targetAction.addCallback {
                callback(self.state)
            }
            bag += Disposer {
                self.removeTarget(targetAction, action: TargetAction.selector)
            }
            return bag
        }.readable(initial: self.state)
    }
    
    /// Returns a signal that will signal only for `state`, equivalent to `filter { $0 == forState }.toVoid()`
    public func signal(forState state: UIGestureRecognizerState) -> Signal<()> {
        return filter { $0 == state }.toVoid()
    }
}

private extension _KeyValueCodingAndObserving where Self: UIControl {
    func signal<T>(for controlEvents: UIControlEvents, keyPath: ReferenceWritableKeyPath<Self, T>) -> ReadWriteSignal<T> {
        return merge(signal(for: controlEvents).readable(), signal(for: keyPath).toVoid()).map { self[keyPath: keyPath] }.writable { self[keyPath: keyPath] = $0 }
    }
}
    
private extension Optional {
    subscript(fallback fallback: Wrapped) -> Wrapped {
        get { return self ?? fallback }
        set { self = newValue }
    }
}

#endif


