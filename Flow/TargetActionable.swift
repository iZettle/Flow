//
//  TargetActionable.swift
//  Flow
//
//  Created by Måns Bernhardt on 2015-09-17.
//  Copyright © 2015 iZettle. All rights reserved.
//

import Foundation


/// Whether the conforming object supports a single target and action.
public protocol TargetActionable: class {
    var action: Selector? { get set }
    var target: AnyObject? { get set }
}

// Default `SignalProvider` conformance for `TargetActionable`s
public extension SignalProvider where Self: TargetActionable {
    var providedSignal: ReadSignal<()> {
        assert(target == nil || target is TargetAction, "You can only install one target")
        
        var targetAction: TargetAction!
        if let ta = target as? TargetAction {
            targetAction = ta
            assert(action == TargetAction.selector, "You can't change the selector")
        } else {
            targetAction = TargetAction()
            target = targetAction
            action = TargetAction.selector
        }
        
        (self as? AutoEnablable&HasEventListeners)?.updateAutomaticEnabling()
        
        return Signal { callback in
            let d = targetAction.addCallback(callback)
            return Disposer {
                d.dispose()
                if targetAction.callbacker.isEmpty {
                    self.target = nil
                    self.action = nil
                    (self as? AutoEnablable&HasEventListeners)?.updateAutomaticEnabling()
                }
            }
        }.readable()
    }
}

extension TargetActionable where Self: AutoEnablable {
    public var hasEventListeners: Bool {
        return target is TargetAction
    }
}

// Helper class to setup target actions.
final class TargetAction: NSObject {
    public static let selector: Selector = #selector(TargetAction.__onAction)
    fileprivate let callbacker = Callbacker<()>()
    
    public func addCallback(_ callback: @escaping () -> Void) -> Disposable {
        return callbacker.addCallback(callback)
    }
    
    @objc func __onAction() {
        callbacker.callAll()
    }
}


