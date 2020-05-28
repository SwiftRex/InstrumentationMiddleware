import os.signpost
import SwiftRex

public class InstrumentationMiddleware<M: Middleware>: Middleware {
    public let middleware: M
    private let prefix: String
    private let log: OSLog
    private var storeOutput: AnyActionHandler<M.OutputActionType>?

    public init(middleware: M, prefix: String, log: OSLog) {
        self.middleware = middleware
        self.prefix = prefix
        self.log = log
    }

    public func receiveContext(getState: @escaping GetState<M.StateType>, output: AnyActionHandler<M.OutputActionType>) {
        self.storeOutput = output
        let proxiedOutput = AnyActionHandler<M.OutputActionType>.init { [weak self] action, source in
            output.dispatch(action, from: source)

            guard let self = self, self.log.signpostsEnabled else { return }
            os_signpost(
                .event,
                log: self.log,
                name: "Middleware Effect", "%sOutput %s from %s",
                self.prefix,
                debugCaseOutput(action),
                [source.file, String(source.line), source.info].compactMap { $0 }.joined(separator: ":")
            )
        }
        self.middleware.receiveContext(getState: getState, output: proxiedOutput)
    }

    public func handle(action: M.InputActionType, from dispatcher: ActionSource, afterReducer: inout AfterReducer) {
        let log = self.log
        guard log.signpostsEnabled else {
            self.middleware.handle(action: action, from: dispatcher, afterReducer: &afterReducer)
            return
        }

        let zeroWidthSpace = "\u{200B}"
        let prefix = self.prefix.isEmpty ? zeroWidthSpace : "[\(self.prefix)] "

        let actionOutput = debugCaseOutput(action)
        if log.signpostsEnabled {
            os_signpost(.begin, log: log, name: "Action", "%s%s", prefix, actionOutput)
        }

        var innerMiddlewareAfterReducer: AfterReducer = .doNothing()
        self.middleware.handle(action: action, from: dispatcher, afterReducer: &innerMiddlewareAfterReducer)

        afterReducer = .do {
            if log.signpostsEnabled {
                os_signpost(.end, log: log, name: "Action")
            }
        } <> innerMiddlewareAfterReducer
    }
}

extension Middleware {
    public func signpost(
        prefix: String = "",
        log: OSLog = OSLog(subsystem: "de.developercity.swiftrex", category: "SwiftRex Middleware")
    ) -> InstrumentationMiddleware<Self> {
        .init(middleware: self, prefix: prefix, log: log)
    }
}

private func debugCaseOutput(_ value: Any) -> String {
    let mirror = Mirror(reflecting: value)
    switch mirror.displayStyle {
    case .enum:
        guard let child = mirror.children.first else {
            let childOutput = "\(value)"
            return childOutput == "\(type(of: value))" ? "" : ".\(childOutput)"
        }
        let childOutput = debugCaseOutput(child.value)
        return ".\(child.label ?? "")\(childOutput.isEmpty ? "" : "(\(childOutput))")"
    case .tuple:
        return mirror.children.map { label, value in
            let childOutput = debugCaseOutput(value)
            return "\(label.map { "\($0):" } ?? "")\(childOutput.isEmpty ? "" : " \(childOutput)")"
        }
        .joined(separator: ", ")
    default:
        return "\(value)"
    }
}
