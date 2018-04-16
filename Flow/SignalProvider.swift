//
//  SignalProvider.swift
//  Flow
//
//  Created by Måns Bernhardt on 2015-09-17.
//  Copyright © 2015 iZettle. All rights reserved.
//

import Foundation

/// Allows conforming types to provide a default signal.
/// By implementing signal transforms such as `map()` as extensions on `SignalProvider`,
/// these transforms could be used directly on conforming types.
///
///     extension UITextField: SignalProvider { ... }
///
///     bag += textField.map { $0.isValidPassword }.onValue { isEnabled = $0 }
///
/// As `CoreSignal` the base of `Signal`, `ReadSignal`, `ReadWriteSignal` and `FiniteSignal`, also conforms to `SignalProvider`,
/// transforms should only be implemented on `SignalProvider`.
///
///     extension SignalProvider {
///       func map<T>(_ transform: @escaping (Value) -> T) -> CoreSignal<Kind.DropWrite, T>
///     }
public protocol SignalProvider {
    associatedtype Value
    
    /// What access (`Plain`, `Read`, `ReadWrite` or `Finite`) the provided signal has
    associatedtype Kind: SignalKind
    
    /// The signal used when doing transformation on conforming types.
    var providedSignal: CoreSignal<Kind, Value> { get }
}

/// Specifies the kind of a signal, `Plain`, `Read` or `ReadWrite`.
public protocol SignalKind {
    associatedtype DropWrite: SignalKind /// The type of self without write access
    associatedtype DropReadWrite: SignalKind /// The type of self without read nor write access
    associatedtype PotentiallyRead: SignalKind // The type of self if self could become readable.
}

public extension SignalKind {
    static var isReadable: Bool { return DropWrite.self == Read.self  }
}

/// A signal kind with no read nor write access
public enum Plain: SignalKind {
    public typealias DropWrite = Plain
    public typealias DropReadWrite = Plain
    public typealias PotentiallyRead = Read
}

/// A signal kind with read access but no write access
public enum Read: SignalKind {
    public typealias DropWrite = Read
    public typealias DropReadWrite = Plain
    public typealias PotentiallyRead = Read
}

/// A signal kind with both read and write access
public enum ReadWrite: SignalKind {
    public typealias DropWrite = Read
    public typealias DropReadWrite = Plain
    public typealias PotentiallyRead = Read
}

/// A signal kind that can terminate
public enum Finite: SignalKind {
    public typealias DropWrite = Finite
    public typealias DropReadWrite = Finite
    public typealias PotentiallyRead = Finite
}
