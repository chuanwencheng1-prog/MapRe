//
//  KPLogger.swift
//  KernelPanel
//

import Foundation
import Darwin
import Combine
import SwiftUI

let globallogger = KPLogger()

class KPLogger: ObservableObject {
    @Published var logs: [String] = []

    private var lastmessage: String?
    private var repeatCount = 0
    private var stdoutpipe: Pipe?
    private var panding = ""
    private var ogstdout: Int32 = -1
    private var ogstderr: Int32 = -1

    private let ignoredlogsubstrings = [
        "Faulty glyph",
        "outline detected",
        "Gesture:",
        "tcp_output [",
        "Error Domain=",
        "com.apple.UIKit",
        "OSLOG",
        "_UISystemGestureGate",
        "NSError",
        "UITouch",
        "gestureRecognizers",
        "graph: {(",
        "UILongPressGestureRecognizer",
        "UIScrollViewPan",
        "SwiftUI.UIHostingView",
        "NSLayoutConstraint",
    ]

    init() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let separator = "KernelPanel started: \(formatter.string(from: Date()))"
        self.logs = [separator]
    }

    func log(_ message: String) {
        DispatchQueue.main.async {
            if message == self.lastmessage {
                self.repeatCount += 1
                if let lastIndex = self.logs.indices.last {
                    self.logs[lastIndex] = "\(message) (\(self.repeatCount + 1)x)"
                }
            } else {
                self.repeatCount = 0
                self.logs.append(message)
                self.lastmessage = message
            }
        }
        emit(message)
    }

    func divider() {
        DispatchQueue.main.async {
            self.lastmessage = nil
            self.repeatCount = 0
        }
    }

    func clear() {
        DispatchQueue.main.async {
            self.logs.removeAll()
            self.lastmessage = nil
            self.repeatCount = 0
        }
    }

    func capture() {
        if stdoutpipe != nil { return }

        let pipe = Pipe()
        stdoutpipe = pipe

        ogstdout = dup(STDOUT_FILENO)
        ogstderr = dup(STDERR_FILENO)

        setvbuf(stdout, nil, _IOLBF, 0)
        setvbuf(stderr, nil, _IOLBF, 0)

        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            guard let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { return }
            self?.appendraw(chunk)
        }
    }

    func stopcapture() {
        guard let pipe = stdoutpipe else { return }
        pipe.fileHandleForReading.readabilityHandler = nil

        if ogstdout != -1 {
            dup2(ogstdout, STDOUT_FILENO)
            close(ogstdout)
            ogstdout = -1
        }
        if ogstderr != -1 {
            dup2(ogstderr, STDERR_FILENO)
            close(ogstderr)
            ogstderr = -1
        }

        try? pipe.fileHandleForWriting.close()
        try? pipe.fileHandleForReading.close()
        stdoutpipe = nil
    }

    private func appendraw(_ chunk: String) {
        var text = panding + chunk
        var lines = text.components(separatedBy: "\n")
        panding = lines.removeLast()
        if !lines.isEmpty {
            let filtered = lines.filter { !shouldignore($0) }
            DispatchQueue.main.async {
                self.logs.append(contentsOf: filtered)
            }
            for line in filtered {
                emit(line)
            }
        }
    }

    private func emit(_ message: String) {
        if shouldignore(message) { return }
        guard ogstdout != -1 else { return }
        let line = message + "\n"
        line.withCString { ptr in
            _ = Darwin.write(ogstdout, ptr, strlen(ptr))
        }
    }

    private func shouldignore(_ message: String) -> Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        for fragment in ignoredlogsubstrings {
            if message.contains(fragment) { return true }
        }
        return false
    }
}
