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
    
    var didLayoutSignal: Signal<()> {
        return signal(for: \.didLayoutCallbacker)
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
