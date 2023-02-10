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

@available(iOS 13.0, macOS 10.15, *)
extension CoreSignal where Kind == ReadWrite {

    var asBinding: Binding<Value> {
        Binding<Value>(
            get: { self.value },
            set: { self.value = $0 }
        )
    }

}

@available(iOS 13.0, macOS 10.15, *)
extension CoreSignal where Kind == Read {

    var asBinding: Binding<Value> {
        Binding<Value>(
            get: { self.value },
            set: { _ in }
        )
    }
    
}
#endif
