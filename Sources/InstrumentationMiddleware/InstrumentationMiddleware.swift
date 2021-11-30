import os.signpost
import SwiftRex

public class InstrumentationMiddleware<M: MiddlewareProtocol>: MiddlewareProtocol {
    public let middleware: M
    private let prefix: String
    private let log: OSLog
    private var storeOutput: AnyActionHandler<M.OutputActionType>?

    public init(middleware: M, prefix: String, log: OSLog) {
        self.middleware = middleware
        self.prefix = prefix
        self.log = log
    }

    public func handle(action: M.InputActionType, from dispatcher: ActionSource, state: @escaping GetState<M.StateType>) -> IO<M.OutputActionType> {
        let log = self.log
        guard log.signpostsEnabled else {
            return self.middleware.handle(action: action, from: dispatcher, state: state)
        }

        let zeroWidthSpace = "\u{200B}"
        let prefix = self.prefix.isEmpty ? zeroWidthSpace : "[\(self.prefix)] "
        let actionOutput = debugCaseOutput(action)

        let start = IO<M.OutputActionType> { _ in
            if log.signpostsEnabled {
                os_signpost(.begin, log: log, name: "Action", "%s%s", prefix, actionOutput)
            }
        }

        let end = IO<M.OutputActionType> { _ in
            if log.signpostsEnabled {
                os_signpost(.end, log: log, name: "Action")
            }
        }

        let innerIO =
            middleware
                .handle(action: action, from: dispatcher, state: state)
                .flatMap { (dispatchedAction: DispatchedAction<OutputActionType>) -> IO<OutputActionType> in
                    // Inner middleware IO will dispatch actions, we intercept these actions to perform
                    // the os_signpost side-effect, and immediately forward the original action to the store.
                    IO { output in
                        os_signpost(
                            .event,
                            log: self.log,
                            name: "Middleware Effect", "%sOutput %s from %s",
                            self.prefix,
                            debugCaseOutput(action),
                            [
                                dispatchedAction.dispatcher.file,
                                String(dispatchedAction.dispatcher.line),
                                dispatchedAction.dispatcher.info
                            ].compactMap { $0 }.joined(separator: ":")
                        )

                        output.dispatch(dispatchedAction)
                    }
                }
        return start <> innerIO <> end
    }
}

extension MiddlewareProtocol {
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
