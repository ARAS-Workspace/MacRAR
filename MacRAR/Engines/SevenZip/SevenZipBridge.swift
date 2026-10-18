import Foundation

enum SevenZipBridge {

    // MARK: - Result

    enum Code {
        case ok
        case warning
        case invalidParameter
        case notArchive
        case passwordRequired
        case wrongPassword
        case cancelled
        case unsupported
        case dataError
        case noMemory
        case failed

        init(_ code: Int32) {
            switch code {
            case SEVENZIP_OK: self = .ok
            case SEVENZIP_WARNING: self = .warning
            case SEVENZIP_ERR_INVALID_PARAM: self = .invalidParameter
            case SEVENZIP_ERR_NOT_ARCHIVE: self = .notArchive
            case SEVENZIP_ERR_PASSWORD_REQUIRED: self = .passwordRequired
            case SEVENZIP_ERR_WRONG_PASSWORD: self = .wrongPassword
            case SEVENZIP_ERR_CANCELLED: self = .cancelled
            case SEVENZIP_ERR_UNSUPPORTED: self = .unsupported
            case SEVENZIP_ERR_DATA: self = .dataError
            case SEVENZIP_ERR_NO_MEMORY: self = .noMemory
            default: self = .failed
            }
        }

        var succeeded: Bool { self == .ok || self == .warning }
        var isPasswordProblem: Bool { self == .passwordRequired || self == .wrongPassword }
    }

    struct Outcome {
        let code: Code
        /// sevenzip_last_error() for a failed call, empty otherwise
        let error: String
        /// Per-item errors and warnings, in the order they were reported
        let messages: [String]
    }

    // MARK: - Listing

    struct Item {
        let path: String
        let method: String
        let size: UInt64
        let packedSize: UInt64
        let modified: Date?
        let crc: UInt32?
        let isDirectory: Bool
        let encrypted: Bool
    }

    struct Listing {
        let type: String
        let container: String
        let solid: Bool
        let volumes: UInt32
        let headersEncrypted: Bool
        let items: [Item]
    }

    static func list(_ archive: String, password: String?) -> Result<Listing, Failure> {
        var handle: OpaquePointer?
        let code = Code(sevenzip_list(archive, password, &handle))
        guard code.succeeded, let handle else { return .failure(Failure(code: code, message: lastError)) }
        defer { sevenzip_listing_free(handle) }

        var items: [Item] = []
        let count = sevenzip_listing_count(handle)
        items.reserveCapacity(Int(count))
        var raw = SevenZipItem()
        for index in 0..<count where sevenzip_listing_item(handle, index, &raw) {
            items.append(Item(
                path: String(cString: raw.path),
                method: String(cString: raw.method),
                size: raw.size,
                packedSize: raw.packed_size,
                modified: raw.mtime != 0 ? Date(timeIntervalSince1970: TimeInterval(raw.mtime)) : nil,
                crc: raw.has_crc ? raw.crc : nil,
                isDirectory: raw.is_dir,
                encrypted: raw.encrypted
            ))
        }
        return .success(Listing(
            type: String(cString: sevenzip_listing_type(handle)),
            container: String(cString: sevenzip_listing_container(handle)),
            solid: sevenzip_listing_is_solid(handle),
            volumes: sevenzip_listing_volumes(handle),
            headersEncrypted: sevenzip_listing_headers_encrypted(handle),
            items: items
        ))
    }

    struct Failure: Error {
        let code: Code
        let message: String
    }

    // MARK: - Operations

    enum Overwrite {
        case overwrite, rename, skip

        var raw: Int32 {
            switch self {
            case .overwrite: return SEVENZIP_OVERWRITE
            case .rename: return SEVENZIP_RENAME
            case .skip: return SEVENZIP_SKIP
            }
        }
    }

    struct UpdateOptions {
        var format: String
        var level: Int32 = -1
        var solid: Int32 = -1
        var password: String?
        var encryptHeaders = false
        var zipAES256 = false
        var volumeSize: UInt64 = 0
        var deleteSources = false
    }

    enum Operation {
        case extract(archive: String, destination: String, items: [String]?, overwrite: Overwrite, password: String?)
        case test(archive: String, password: String?)
        case update(archive: String, sources: [String], options: UpdateOptions)
        case delete(archive: String, items: [String], password: String?, encryptHeaders: Bool)
    }

    static var version: String { String(cString: sevenzip_get_version()) }

    /// The code pages ZIP names stored in a Windows code page are read with. nil, as before the app sets them for the
    /// user's region at launch, reads them as 7-Zip does on macOS: each byte past ASCII becomes an escape. Set it only
    /// while no operation runs.
    static var windowsCodePages: WindowsCodePages? {
        didSet { sevenzip_set_code_pages(windowsCodePages?.oem ?? 0, windowsCodePages?.ansi ?? 0) }
    }

    private static var lastError: String { String(cString: sevenzip_last_error()) }

    // MARK: - Job

    /// Runs one operation off the main thread; progress, items and the outcome arrive on the main queue.
    final class Job {
        var onProgress: ((Double) -> Void)?
        var onItem: ((String) -> Void)?

        private let lock = NSLock()
        private var cancelled = false
        private var lastPermille = -1
        private var messages: [String] = []

        func cancel() {
            lock.lock(); cancelled = true; lock.unlock()
        }

        func start(_ operation: Operation, completion: @escaping (Outcome) -> Void) {
            DispatchQueue.global(qos: .userInitiated).async {
                let code = Code(self.run(operation))
                let outcome = Outcome(code: code, error: code.succeeded ? "" : SevenZipBridge.lastError, messages: self.messages)
                DispatchQueue.main.async { completion(outcome) }
            }
        }

        private func run(_ operation: Operation) -> Int32 {
            var callbacks = SevenZipCallbacks(
                context: Unmanaged.passUnretained(self).toOpaque(),
                progress: Job.progressThunk,
                item: Job.itemThunk,
                message: Job.messageThunk
            )
            switch operation {
            case let .extract(archive, destination, items, overwrite, password):
                return withCStrings(items ?? []) { names, count in
                    sevenzip_extract(archive, destination, items == nil ? nil : names, count, overwrite.raw, password, &callbacks)
                }
            case let .test(archive, password):
                return sevenzip_test(archive, password, &callbacks)
            case let .update(archive, sources, options):
                return withCStrings(sources) { paths, count in
                    withOptionalCString(options.password) { password in
                        options.format.withCString { format in
                            var raw = SevenZipUpdateOptions(
                                format: format, level: options.level, solid: options.solid, password: password,
                                encrypt_headers: options.encryptHeaders, zip_aes256: options.zipAES256,
                                volume_size: options.volumeSize, delete_sources: options.deleteSources
                            )
                            return sevenzip_update(archive, paths, count, &raw, &callbacks)
                        }
                    }
                }
            case let .delete(archive, items, password, encryptHeaders):
                return withCStrings(items) { names, count in
                    sevenzip_delete(archive, names, count, password, encryptHeaders, &callbacks)
                }
            }
        }

        private static let progressThunk: ProgressCallback = { context, completed, total in
            guard let context else { return false }
            return Unmanaged<Job>.fromOpaque(context).takeUnretainedValue().progress(completed, total)
        }

        private static let itemThunk: TextCallback = { context, path in
            guard let context, let path else { return }
            Unmanaged<Job>.fromOpaque(context).takeUnretainedValue().item(String(cString: path))
        }

        private static let messageThunk: TextCallback = { context, message in
            guard let context, let message else { return }
            Unmanaged<Job>.fromOpaque(context).takeUnretainedValue().messages.append(String(cString: message))
        }

        private func progress(_ completed: UInt64, _ total: UInt64) -> Bool {
            lock.lock()
            let stop = cancelled
            lock.unlock()
            guard total > 0 else { return stop }
            let permille = Int(min(1000, completed * 1000 / total))
            if permille != lastPermille, let onProgress {
                lastPermille = permille
                DispatchQueue.main.async { onProgress(Double(permille) / 1000) }
            }
            return stop
        }

        private func item(_ path: String) {
            guard let onItem else { return }
            DispatchQueue.main.async { onItem(path) }
        }
    }
}

// MARK: - C callbacks and strings

private typealias ProgressCallback = @convention(c) (UnsafeMutableRawPointer?, UInt64, UInt64) -> Bool
private typealias TextCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> Void

private func withCStrings<T>(_ strings: [String], _ body: (UnsafePointer<UnsafePointer<CChar>?>?, Int) -> T) -> T {
    let copies = strings.map { strdup($0) }
    defer { copies.forEach { free($0) } }
    let pointers: [UnsafePointer<CChar>?] = copies.map { $0.map { UnsafePointer($0) } }
    return pointers.withUnsafeBufferPointer { body($0.baseAddress, $0.count) }
}

private func withOptionalCString<T>(_ string: String?, _ body: (UnsafePointer<CChar>?) -> T) -> T {
    guard let string else { return body(nil) }
    return string.withCString { body($0) }
}
