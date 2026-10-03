import Foundation

/// Mail and Numbers scripting runs one script at a time, off the main thread.
let automationQueue = DispatchQueue(label: "com.moqucu.EmailGobbler.automation", qos: .utility)

func onAutomationQueue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { continuation in
        automationQueue.async { continuation.resume(returning: work()) }
    }
}
