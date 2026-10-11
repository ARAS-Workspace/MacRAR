import Foundation

final class RarJob {
    enum Event: Equatable {
        case file(String)       // a new file is being processed
        case progress(Int)      // percentage (overall)
    }

    private var process: Process?
    private let queue = DispatchQueue(label: "macrar.job")
    private var reader = RarOutput()
    private(set) var cancelled = false
    var onEvent: ((Event) -> Void)?   // called on the main queue

    /// `password` answers the question RarRunner.passwordSwitch makes rar ask, byte for byte as typed.
    func start(_ args: [String], cwd: String? = nil, password: String? = nil, completion: @escaping (RarResult) -> Void) {
        let process = RarRunner.makeProcess(args, cwd: cwd)
        if let password {
            // rar reads one line, whatever the command. Written before rar starts, the pipe holds it until rar asks, and
            // nothing is ever written to a rar that has already gone, which would end the app with SIGPIPE
            let input = Pipe()
            try? input.fileHandleForWriting.write(contentsOf: Data((password + "\n").utf8))
            try? input.fileHandleForWriting.close()
            process.standardInput = input
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty, let self else { return }
            self.queue.async { self.consume(data) }
        }
        process.terminationHandler = { [weak self] proc in
            handle.readabilityHandler = nil
            let rest = handle.readDataToEndOfFile()
            guard let self else { return }
            self.queue.async {
                self.consume(rest)
                self.reader.finish()
                let result = RarResult(code: proc.terminationStatus, output: self.reader.log, cancelled: self.cancelled)
                DispatchQueue.main.async { completion(result) }
            }
        }
        self.process = process
        do { try process.run() } catch {
            DispatchQueue.main.async {
                completion(RarResult(code: -1, output: loc.t("could_not_run", error.localizedDescription)))
            }
        }
    }

    func cancel() {
        cancelled = true
        if let process, process.isRunning { process.terminate() }
    }

    private func consume(_ data: Data) {
        let events = reader.read(data)
        guard !events.isEmpty, let onEvent else { return }
        DispatchQueue.main.async { events.forEach(onEvent) }
    }
}
