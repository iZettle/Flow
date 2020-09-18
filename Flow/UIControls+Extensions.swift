//
//  UIControl+Extensions.swift
//  Flow
//
//  Created by Måns Bernhardt on 2015-09-17.
//  Copyright © 2015 PayPal Inc. All rights reserved.
//

#if canImport(UIKit)

import UIKit

public extension UIControl {
    /// Returns a signal that will signal when any event in `controlEvents` is signaled on `self`.
    ///
    ///     bag += textField.signal(for: .editingDidBegin).onValue { ... }
    func signal(for controlEvents: UIControl.Event) -> Signal<()> {
        return Signal(onValue: { callback in
            let targetAction = TargetAction()
            self.addTarget(targetAction, action: TargetAction.selector, for: controlEvents)

            self.updateAutomaticEnabling()

            let bag = DisposeBag()
            bag += targetAction.addCallback { callback(()) }
            bag += Disposer {
                self.removeTarget(targetAction, action: TargetAction.selector, for: controlEvents)
                self.updateAutomaticEnabling()
            }
            return bag
        })
    }
}

extension SignalProvider where Self: UIControl, Kind.DropWrite == Read {
    /// Returns a signal that will signal with the latest value when the control event `.valueChanged` is signaled on `self`.
    /// - Note: This is useful when we need to know the a change was user initiated, whichs is not always the case as typically `UIControl`'s `providedSignal` is triggered on KVO as well.
    var valueChanged: Signal<Value> {
        return signal(for: .valueChanged).map { self.value }
    }
}

extension UIControl: HasEventListeners, AutoEnablable {
    public var hasEventListeners: Bool {
        return !allTargets.filter { $0 is TargetAction }.isEmpty
    }
}

extension UIAlertAction: Enablable {}

extension UIControl: Enablable {}

extension UITextField: SignalProvider {
    public var providedSignal: ReadWriteSignal<String> {
        return signal(for: .editingChanged, keyPath: \.text)[\.[fallback: ""]]
    }
}

extension UIButton: SignalProvider {
    public var providedSignal: Signal<()> {
        return signal(for: .touchUpInside)
    }
}

extension UISegmentedControl: SignalProvider {
    public var providedSignal: ReadWriteSignal<Int> {
        return signal(for: .valueChanged, keyPath: \.selectedSegmentIndex)
            .distinct() // KVO seems to trigger when tapping as well, even when tapping selected.
    }
}

extension UIPageControl: SignalProvider {
    public var providedSignal: ReadWriteSignal<Int> {
        return signal(for: .valueChanged, keyPath: \.currentPage)
    }
}

#if !os(tvOS)

extension UISwitch: SignalProvider {
    public var providedSignal: ReadWriteSignal<Bool> {
        return signal(for: .valueChanged, keyPath: \.isOn)
    }
}

extension UISlider: SignalProvider {
    public var providedSignal: ReadWriteSignal<Float> {
        return signal(for: .valueChanged, keyPath: \.value).distinct()
    }
}

extension UIRefreshControl: SignalProvider {
    public var providedSignal: Signal<()> {
        return signal(for: .valueChanged)
    }
}

public extension UIRefreshControl {
    /// Will animated `self` until the returned `Disposable` is being disposed
    func animate() -> Disposable {
        beginRefreshing()
        return Disposer {
            self.endRefreshing()
        }
    }

    /// Will trigger a refresh by trigger the action .valueChanged
    func refresh() {
        sendActions(for: .valueChanged)
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

#endif

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
        control.addTarget(self, action: #selector(UIBarButtonItem.flowBarSubButton), for: .touchUpInside)
    }

    @objc private func flowBarSubButton() {
        _ = self.target?.perform(self.action)
    }
}

extension UIGestureRecognizer: SignalProvider {
    public var providedSignal: ReadSignal<UIGestureRecognizer.State> {
        return Signal(onValue: { callback in
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
        }).readable(initial: self.state)
    }

    /// Returns a signal that will signal only for `state`, equivalent to `filter { $0 == forState }.toVoid()`
    public func signal(forState state: UIGestureRecognizer.State) -> Signal<()> {
        return filter { $0 == state }.toVoid()
    }
}

public extension UIView {
    /// Will add `recognizer` and remove it when the returned `Disposable` is being diposed.
    func install(_ recognizer: UIGestureRecognizer) -> Disposable {
        addGestureRecognizer(recognizer)
        return Disposer {
            self.removeGestureRecognizer(recognizer)
        }
    }
}

public extension UITextField {
    /// Delegate for asking if editing should stop in the specified text field
    /// - See: UITextFieldDelegate.textFieldShouldEndEditing()
    /// - Note: Any currently set delegate will be overridden, unless the delegate was set by `shouldEndEditing` or `shouldReturn`.
    var shouldEndEditing: Delegate<String, Bool> {
        return Delegate { callback in self.usingDelegate { $0.shouldEndEditing.set(callback) } }
    }

    /// Delegate for asking whether the text field should process the pressing of the return button
    /// - See: UITextFieldDelegate.textFieldShouldReturn()
    /// - Note: Any currently set delegate will be overridden, unless the delegate was set by `shouldEndEditing` or `shouldReturn`.
    var shouldReturn: Delegate<String, Bool> {
        return Delegate { callback in self.usingDelegate { $0.shouldReturn.set(callback) } }
    }

    // A signal whether or not `self` is Editing.
    var isEditingSignal: ReadSignal<Bool> {
        return signal(for: [.editingDidBegin, .editingDidEnd]).readable().map { self.isEditing }
    }
}

#if !os(tvOS)

/// Returns a signal that will signal on orientation changes.
public var orientationSignal: ReadSignal<UIInterfaceOrientation> {
    return NotificationCenter.default.signal(forName: UIApplication.didChangeStatusBarOrientationNotification).map { _ in UIApplication.shared.statusBarOrientation }.readable(capturing: UIApplication.shared.statusBarOrientation)
}

#endif

private extension UITextField {
    class TextFieldDelegate: NSObject, UITextFieldDelegate {
        var shouldEndEditing = Delegate<String, Bool>()
        var shouldReturn = Delegate<String, Bool>()

        func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
            return shouldEndEditing.call(textField.value) ?? true
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            return shouldReturn.call(textField.value) ?? true
        }
    }

    // Make sure to only have one delegate setup (share between users) and release it when done.
    func usingDelegate(_ function: (TextFieldDelegate) -> Disposable) -> Disposable {
        class Weak<T> where T: AnyObject {
            weak var value: T?
            init(_ value: T) { self.value = value }
        }

        let weakDelegate = objc_getAssociatedObject(self, &delegateKey) as? Weak<TextFieldDelegate>
        let delegate = weakDelegate?.value ?? TextFieldDelegate()
        objc_setAssociatedObject(self, &delegateKey, Weak(delegate), .OBJC_ASSOCIATION_RETAIN)
        let bag = DisposeBag()
        self.delegate = delegate
        bag.hold(delegate)
        bag += function(delegate)
        return bag
    }
}

private var delegateKey = 0

private extension _KeyValueCodingAndObserving where Self: UIControl {
    func signal<T>(for controlEvents: UIControl.Event, keyPath: ReferenceWritableKeyPath<Self, T>) -> ReadWriteSignal<T> {
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
