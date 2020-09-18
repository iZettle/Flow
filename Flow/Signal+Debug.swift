//
// Created by Niil Öhlin on 2018-08-14.
// Copyright © 2018 PayPal Inc. All rights reserved.
//

import Foundation

extension SignalProvider {
    /// Prints current event type and date to stdout with the format `HH:mm:ss.SSS: <fileName.swift:line> (function): message -> eventType(value)`.
    /// - parameter message: The message to be printed.
    /// - parameter printer: A callback that should do the printing. Defaults to `print(_:separator:terminator:)`
    public func debug(
        on scheduler: Scheduler = .current,
        _ message: String? = nil,
        printer print: @escaping (String) -> Void = { print($0) },
        file: String = #file,
        line: UInt = #line,
        function: String = #function
        ) -> CoreSignal<Kind, Value> {
        let signal = providedSignal
        let message = message.map { $0 + " -> " } ?? ""
        let fileIdentifier = "<\(file.lastFileComponent):\(line)> (\(function))"
        return CoreSignal(setValue: setter, onEventType: { callback in
            let bag = DisposeBag()
            bag += signal.onEventType(on: scheduler) { eventType in
                let fullMessage = "\(dateFormatter.string(from: Date())): \(fileIdentifier): \(message)"
                switch eventType {
                case .initial(nil):
                    print("\(fullMessage)initial")
                case .initial(let val?):
                    print("\(fullMessage)initial(\(String(describing: val)))")
                case .event(.value(let val)):
                    print("\(fullMessage)event(value(\(val)))")
                case .event(.end(let error)):
                    print("\(fullMessage)event(end(\(String(describing: error))))")
                }
                callback(eventType)
            }
            bag += {
                let identifier = "\(dateFormatter.string(from: Date())): \(fileIdentifier)"
                print("\(identifier): \(message)disposed")
            }
            return bag
        })
    }
}

private let dateFormat = "HH:mm:ss.SSS"
private var dateFormatter: DateFormatter = {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = dateFormat
    return dateFormatter
}()

private extension String {
    var lastFileComponent: String {
        guard let lastIndex = rangeOfCharacter(from: CharacterSet(charactersIn: "/"), options: .backwards, range: nil) else {
            return self
        }

        return String(self[index(after: lastIndex.lowerBound) ..< endIndex])
    }
}
