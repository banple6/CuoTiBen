import Foundation

actor AIRequestSingleFlight<Value> {
    private struct InFlight {
        let token: UUID
        let task: Task<Value, Error>
        var waiterCount: Int
    }

    private var inFlightTasks: [String: InFlight] = [:]

    func run(
        key: String,
        onJoin: (() -> Void)? = nil,
        operation: @escaping () async throws -> Value
    ) async throws -> Value {
        let token: UUID
        let task: Task<Value, Error>

        if var existing = inFlightTasks[key] {
            existing.waiterCount += 1
            inFlightTasks[key] = existing
            onJoin?()
            token = existing.token
            task = existing.task
        } else {
            token = UUID()
            task = Task {
                try await operation()
            }
            inFlightTasks[key] = InFlight(token: token, task: task, waiterCount: 1)
        }

        return try await withTaskCancellationHandler {
            do {
                let value = try await task.value
                finish(key: key, token: token)
                return value
            } catch {
                finish(key: key, token: token)
                throw error
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(key: key, token: token)
            }
        }
    }

    private func finish(key: String, token: UUID) {
        guard inFlightTasks[key]?.token == token else { return }
        inFlightTasks.removeValue(forKey: key)
    }

    private func cancelWaiter(key: String, token: UUID) {
        guard var inFlight = inFlightTasks[key], inFlight.token == token else { return }
        inFlight.waiterCount -= 1

        if inFlight.waiterCount <= 0 {
            inFlight.task.cancel()
            inFlightTasks.removeValue(forKey: key)
        } else {
            inFlightTasks[key] = inFlight
        }
    }
}
