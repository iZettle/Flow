//
//  UIView+EditingMenu.swift
//  Flow
//
//  Created by Måns Bernhardt on 2015-09-17.
//  Copyright © 2015 iZettle. All rights reserved.
//

#if canImport(UIKit)

import UIKit


public extension UIView {
    /// Returns a signal that will signal when user selects the copy command from the editing menu.
    /// - Note: Will display an editing menu on long press including the pasteboard actions currently listened on.
    var copySignal: Signal<()> {
        return Signal { c in
            let bag = DisposeBag()
            bag += self.copyingView.copyCallbacker.addCallback(c)
            bag += { self.cleanUpCopyingView() }
            return bag
        }
    }
    
    /// Returns a signal that will signal when user selects the paste command from the editing menu.
    /// - Note: Will display an editing menu on long press including the pasteboard actions currently listened on.
    var pasteSignal: Signal<()> {
        return Signal { c in
            let bag = DisposeBag()
            bag += self.copyingView.pasteCallbacker.addCallback(c)
            bag += { self.cleanUpCopyingView() }
            return bag
        }
    }
    
    /// Returns a signal that will signal when user selects the cut command from the editing menu.
    /// - Note: Will display an editing menu on long press including the pasteboard actions currently listened on.
    var cutSignal: Signal<()> {
        return Signal { c in
            let bag = DisposeBag()
            bag += self.copyingView.cutCallbacker.addCallback(c)
            bag += { self.cleanUpCopyingView() }
            return bag
        }
    }
}

private extension UIView {
    var copyingView: CopyingView {
        return subviews.compactMap { $0 as? CopyingView }.first ?? { let v = CopyingView(); insertSubview(v, at: 0); return v }()
    }
    
    func cleanUpCopyingView() {
        let copyingView = self.copyingView
        if !copyingView.hasListeners { copyingView.removeFromSuperview() }
    }
}

private class CopyingView: UIView {
    private let bag = DisposeBag()
    
    fileprivate let copyCallbacker = Callbacker<()>()
    fileprivate let pasteCallbacker = Callbacker<()>()
    fileprivate let cutCallbacker = Callbacker<()>()
    
    required init() {
        super.init(frame: .zero)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var hasListeners: Bool {
        return !copyCallbacker.isEmpty || !pasteCallbacker.isEmpty || !cutCallbacker.isEmpty
    }
    
    override func didMoveToSuperview() {
        bag.dispose()
        bag += attachLongPressRecognizer()
    }

    override func layoutSubviews() {
        frame = superview?.bounds ?? .zero
        super.layoutSubviews()
    }

    func attachLongPressRecognizer() -> Disposable {
        guard let superview = superview else { return NilDisposer() }
        superview.isUserInteractionEnabled = true
        let bag = DisposeBag()
        let longPressGesture = UILongPressGestureRecognizer()
        bag += install(longPressGesture)
        bag += longPressGesture.signal(forState: .began).onValue { [weak self] in
            let menu = UIMenuController.shared
            guard !menu.isMenuVisible else { return }
            self?.becomeFirstResponder()
            menu.setTargetRect(superview.bounds, in: superview)
            menu.isMenuVisible = true
        }
        return bag
    }
    
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        switch action {
        case #selector(copy(_:)):
            return !copyCallbacker.isEmpty
        case #selector(paste(_:)):
            return !pasteCallbacker.isEmpty
        case #selector(cut(_:)):
            return !cutCallbacker.isEmpty
        default:
            return false
        }
    }
    
    override func copy(_ sender: Any?) {
        copyCallbacker.callAll(with: ())
    }
    
    override func paste(_ sender: Any?) {
        pasteCallbacker.callAll(with: ())
    }
    
    override func cut(_ sender: Any?) {
        cutCallbacker.callAll(with: ())
    }
    
    override var canBecomeFirstResponder: Bool {
        return true
    }
    
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return true
    }
}

#endif
