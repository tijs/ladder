import Foundation
import LadderKit
import Photos

@main
struct Ladder {
    static func main() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized else {
            fatalExit(
                "Photos access not authorized (status: \(status.rawValue)). "
                    + "Grant access in System Settings > Privacy & Security > Photos."
            )
        }

        let request: ExportRequest
        do {
            request = try parseInput()
        } catch {
            fatalExit("Failed to parse input: \(error.localizedDescription)")
        }

        let stagingURL: URL
        do {
            stagingURL = try PathSafety.validateStagingDir(request.stagingDir)
            try FileManager.default.createDirectory(
                at: stagingURL,
                withIntermediateDirectories: true
            )
        } catch {
            fatalExit(error.localizedDescription)
        }

        let exporter = PhotoExporter(
            stagingDir: stagingURL,
            scriptExporter: AppleScriptRunner()
        )

        // Pre-flight: verify Automation permission before starting exports
        do {
            try await exporter.checkPermissions()
        } catch {
            fatalExit(error.localizedDescription)
        }

        let response = await exporter.export(uuids: request.uuids)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(response)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            fatalExit("Failed to encode response: \(error.localizedDescription)")
        }
    }

    private static func parseInput() throws -> ExportRequest {
        let data: Data

        if CommandLine.arguments.count > 1 {
            let filePath = CommandLine.arguments[1]
            data = try Data(contentsOf: URL(fileURLWithPath: filePath))
        } else {
            let stdinData = FileHandle.standardInput.readDataToEndOfFile()
            guard stdinData.count < 10_000_000 else {
                throw ExportFailure.invalidStagingDir("Input exceeds 10 MB limit")
            }
            data = stdinData
        }

        return try JSONDecoder().decode(ExportRequest.self, from: data)
    }

    private static func fatalExit(_ message: String) -> Never {
        FileHandle.standardError.write(Data("ladder: \(message)\n".utf8))
        exit(1)
    }
}
