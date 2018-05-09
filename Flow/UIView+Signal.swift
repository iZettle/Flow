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
    /// Returns the current traitCollection or the screen's traitCollection if `self` has no window
    var traitCollectionWithFallback: UITraitCollection {
        return hasWindowTraitCollection ?? UIScreen.main.traitCollection
    }
}

public extension UIView {
    /// Returns a signal signaling self's subviews when it updates
    var subviewsSignal: ReadSignal<[UIView]> {
        return ReadSignal(capturing: self.subviews) { c in
            self.signal(for: \.layer.sublayers).onValue { _ in
                DispatchQueue.main.async { // Since we listen on sublayers, there could be a mismatch when moving a subview (subview counted twice)
                    c(self.subviews)
                }
            }
        }
    }
    
    /// Returns a signal signaling all of self's subviews when it updates
    var allSubviewsSignal: ReadSignal<[UIView]> {
        return ReadSignal(capturing: self.allSubviews) { callback in
            let bag = DisposeBag()
            let treeChangeBag = DisposeBag()
            bag += treeChangeBag
            let updateSignal: () -> Void = recursive { updateSignal in
                treeChangeBag.dispose()
                let treeChangeSignal = merge(self.allSubviews.compactMap { $0.subviewsSignal })
                treeChangeBag += treeChangeSignal.onFirstValue { _ in
                    callback(self.allSubviews)
                    updateSignal()
                }
            }
            bag += { _ = updateSignal }
            updateSignal()
            return bag
        }
    }
}

private extension UITraitEnvironment {
    var hasWindowTraitCollection: UITraitCollection? {
        switch self {
        case let v as UIView where v.window != nil: return v.traitCollection
        case let v as UIViewController where v.isViewLoaded && v.view?.window != nil: return v.traitCollection
        default: return nil
        }
    }
}


private extension UIView {
    func signal<T>(for keyPath: KeyPath<CallbackerView, Callbacker<T>>) -> Signal<T> {
        return Signal { c in
            let view = (self.viewWithTag(987892442) as? CallbackerView)  ?? {
                let v = CallbackerView(frame: self.bounds)
                v.autoresizingMask = [.flexibleWidth, .flexibleHeight] // trick so layoutsubViews is called when the view is resized
                v.tag = 987892442
                v.backgroundColor = .clear
                v.isUserInteractionEnabled = false
                self.insertSubview(v, at: 0)
                v.setNeedsLayout()
                return v
            }()
            
            view.refCount += 1
            
            let bag = DisposeBag()
            
            bag += {
                view.refCount -= 1
                if view.refCount == 0 {
                    view.removeFromSuperview()
                }
            }
            
            bag += view[keyPath: keyPath].addCallback(c)
            
            return bag
        }
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
