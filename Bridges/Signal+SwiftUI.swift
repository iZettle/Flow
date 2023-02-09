//
//  Signal+SwiftUI.swift
//  Flow
//
//  Created by Martin Andonoski on 2023-02-09.
//  Copyright © 2023 PayPal Inc. All rights reserved.
//

import Foundation
#if canImport(SwiftUI)
import SwiftUI

extension CoreSignal where Kind == ReadWrite {

    @available(iOS 13.0, macOS 10.15, *)
    func asBinding() -> Binding<Value> {
        Binding<Value>(
            get: { self.value },
            set: { self.value = $0 }
        )
    }

}

extension CoreSignal where Kind == Read {

    @available(iOS 13.0, macOS 10.15, *)
    func asBinding() -> Binding<Value> {
        Binding<Value>(
            get: { self.value },
            set: { _ in }
        )
    }
    
}
#endif
