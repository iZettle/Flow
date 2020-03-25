//
//  UIView+Signal.swift
//  Flow
//
//  Created by Måns Bernhardt on 2017-11-07.
//  Copyright © 2017 iZettle. All rights reserved.
//

#if canImport(UIKit)

import UIKit

public extension UIView {
    var windowSignal: ReadSignal<UIWindow?> {
        return signal(for: \.windowCallbacker).readable(capturing: self.window)
    }

    var hasWindowSignal: ReadSignal<Bool> {
        return windowSignal.map { $0 != nil }
    }

    var didMoveToWindowSignal: Signal<()> {
        return hasWindowSignal.filter { $0 }.toVoid()
    }

    var didMoveFromWindowSignal: Signal<()> {
        return hasWindowSignal.filter { !$0 }.toVoid()
    }

    var traitCollectionSignal: ReadSignal<UITraitCollection> {
        return signal(for: \.traitCollectionCallbacker).readable(capturing: self.traitCollection)
    }

    /// Will use traitCollectionWithFallback as source
    var traitCollectionWithFallbackSignal: ReadSignal<UITraitCollection> {
        return traitCollectionSignal.map { _ in self.traitCollectionWithFallback }
    }

    var didLayoutSignal: Signal<()> {
        return signal(for: \.didLayoutCallbacker)
    }
}

public extension UITraitEnvironment {
    /// Returns the current traitCollection.
    ///
    /// Prior iOS 13 (where the traitCollection is always available), there is a fallback if `self` has no window - it falls back to the app's key window traitCollection or if that's not available to the main screen's traitCollection.
    var traitCollectionWithFallback: UITraitCollection {
        guard #available (iOS 13, *) else {
            switch self {
            case let view as UIView where view.window != nil: return view.traitCollection
            case let viewController as UIViewController where viewController.isViewLoaded && viewController.view?.window != nil: return viewController.traitCollection
            default: return UIApplication.shared.keyWindow?.traitCollection ?? UIScreen.main.traitCollection
            }
        }
        return self.traitCollection
    }
}

public extension UIView {
    /// Returns a signal signaling self's subviews when it updates
    var subviewsSignal: ReadSignal<[UIView]> {
        return ReadSignal(capturing: self.subviews) { callback in
            self.signal(for: \.layer.sublayers).onValue { _ in
                DispatchQueue.main.async { // Since we listen on sublayers, there could be a mismatch when moving a subview (subview counted twice)
                    callback(self.subviews)
                }
            }
        }
    }

    /// Returns a signal signaling all of self's descendants when it updates
    var allDescendantsSignal: ReadSignal<[UIView]> {
        return ReadSignal(capturing: self.allDescendants) { callback in
            let bag = DisposeBag()
            let treeChangeBag = DisposeBag()
            bag += treeChangeBag
            let updateSignal: () -> Void = recursive { updateSignal in
                treeChangeBag.dispose()
                let treeChangeSignal = merge(self.allDescendants.compactMap { $0.subviewsSignal })
                treeChangeBag += treeChangeSignal.onFirstValue { _ in
                    callback(self.allDescendants)
                    updateSignal()
                }
            }
            bag += { _ = updateSignal }
            updateSignal()
            return bag
        }
    }

    @available(*, deprecated, renamed: "allDescendantsSignal")
    var allSubviewsSignal: ReadSignal<[UIView]> {
        return allDescendantsSignal
    }
}

private extension UIView {
    func signal<T>(for keyPath: KeyPath<CallbackerView, Callbacker<T>>) -> Signal<T> {
        return Signal(onValue: { callback in
            let view = (self.viewWithTag(987892442) as? CallbackerView)  ?? {
                let view = CallbackerView(frame: self.bounds)
                view.autoresizingMask = [.flexibleWidth, .flexibleHeight] // trick so layoutsubViews is called when the view is resized
                view.tag = 987892442
                view.backgroundColor = .clear
                view.isUserInteractionEnabled = false
                self.insertSubview(view, at: 0)
                view.setNeedsLayout()
                return view
            }()

            view.refCount += 1

            let bag = DisposeBag()

            bag += {
                view.refCount -= 1
                if view.refCount == 0 {
                    view.removeFromSuperview()
                }
            }

            bag += view[keyPath: keyPath].addCallback(callback)

            return bag
        })
    }
}

private class CallbackerView: UIView {
    let windowCallbacker = Callbacker<UIWindow?>()
    let traitCollectionCallbacker = Callbacker<UITraitCollection>()
    let didLayoutCallbacker = Callbacker<()>()
    var refCount = 0

    override fileprivate func didMoveToWindow() {
        super.didMoveToWindow()
        windowCallbacker.callAll(with: window)
    }

    fileprivate override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        traitCollectionCallbacker.callAll(with: traitCollection)
    }

    override fileprivate func layoutSubviews() {
        super.layoutSubviews()
        didLayoutCallbacker.callAll()
    }

    // Tap through
    fileprivate override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return false
    }
}

#endif
