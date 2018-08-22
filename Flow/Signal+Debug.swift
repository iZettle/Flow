//
// Created by Niil Öhlin on 2018-08-14.
// Copyright (c) 2018 iZettle. All rights reserved.
//

import Foundation

private let dateFormat = "HH:mm:ss.SSS"
private var dateFormatter: DateFormatter = {
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = dateFormat
    return dateFormatter
}()

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
        return CoreSignal(onEventType: { callback in
            let bag = DisposeBag()
            let fileIdentifier = "<\(file.lastFileComponent):\(line)> (\(function))"
            bag += signal.onEventType(on: scheduler) { eventType in
                let identifier = "\(dateFormatter.string(from: Date())): \(fileIdentifier)"
                switch eventType {
                case .initial(nil):
                    print("\(identifier): \(message)initial")
                    callback(.initial(nil))
                case .initial(let val?):
                    print("\(identifier): \(message)initial(\(String(describing: val)))")
                    callback(.initial(val))
                case .event(.value(let val)):
                    print("\(identifier): \(message)event(value(\(val)))")
                    callback(.event(.value(val)))
                case .event(.end(let error)):
                    print("\(identifier): \(message)event(end(\(String(describing: error))))")
                    callback(.event(.end(error)))
                }
            }
            bag += {
                let identifier = "\(dateFormatter.string(from: Date())): \(fileIdentifier)"
                print("\(identifier): \(message)disposed")
            }
            return bag
        })
    }
}

private extension String {
    var lastFileComponent: String {
        guard let lastIndex = rangeOfCharacter(from: CharacterSet(charactersIn: "/"), options: .backwards, range: nil) else {
            return self
        }
        
        return String(self[index(after: lastIndex.lowerBound) ..< endIndex])
    }
}
