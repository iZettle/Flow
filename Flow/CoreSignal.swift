//
//  CoreSignal.swift
//  Flow
//
//  Created by Måns Bernhardt on 2016-01-29.
//  Copyright © 2016 iZettle. All rights reserved.
//

import Foundation


/// Used to share functionality and implementations between the four kinds of signals, `Signal`, `ReadSignal`, `ReadWriteSignal` and `FiniteSignal`.
///
///     typealias Signal<Value> = CoreSignal<Plain, Value>
///     typealias ReadSignal<Value> = CoreSignal<Read, Value>
///     typealias ReadWriteSignal<Value> = CoreSignal<ReadWrite, Value>
///     typealias FiniteSignal<Value> = CoreSignal<Finite, Value>
///
/// Most client code will only be confronted with the above type aliases, but for more generic functionality,
/// applicable to more than one of kind of signal, it often makes sense to work directly with `CoreSignal` to
/// allow sharing of implemtenations.
public final class CoreSignal<Kind: SignalKind, Value> {
    internal let onEventType: (@escaping (EventType) -> Void) -> Disposable
    
    public typealias Event = Flow.Event<Value>
    typealias EventType = Flow.EventType<Value>

    internal init(onEventType: @escaping (@escaping (EventType) -> Void) -> Disposable, _ noTrailingClosure: Void = ()) {
        self.onEventType = onEventType
    }
}

// CoreSignal is itself a `SignalProvider`, allowing us to add transforms only to `SignalProvider`, instead of both `CoreSignal` and `SignalProvider`.
extension CoreSignal: SignalProvider {
    public var providedSignal: CoreSignal<Kind, Value> { return self }
}
