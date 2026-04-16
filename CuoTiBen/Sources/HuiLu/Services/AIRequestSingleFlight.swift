import Foundation

actor AIRequestSingleFlight<Value> {
    private var inFlightTasks: [String: Task<Value, Error>] = [:]

    func run(
        key: String,
        onJoin: (() -> Void)? = nil,
        operation: @escaping () async throws -> Value
    ) async throws -> Value {
        if let existingTask = inFlightTasks[key] {
            onJoin?()
            return try await existingTask.value
        }

        let task = Task {
            try await operation()
        }
        inFlightTasks[key] = task

        do {
            let value = try await task.value
            inFlightTasks.removeValue(forKey: key)
            return value
        } catch {
            inFlightTasks.removeValue(forKey: key)
            throw error
        }
    }
}
