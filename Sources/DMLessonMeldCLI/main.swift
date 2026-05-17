import DMLessonMeldCore
import CoreGraphics
import Foundation

@main
struct DMLessonMeldCLI {
    static func main() {
        do {
            try run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            Foundation.exit(1)
        }
    }

    static func run(_ arguments: [String]) throws {
        guard let command = arguments.first else {
            printHelp()
            return
        }

        switch command {
        case "--help", "-h", "help":
            printHelp()
        case "project":
            try runProject(Array(arguments.dropFirst()))
        case "record":
            try awaitCompatibleRecord(Array(arguments.dropFirst()))
        case "permissions":
            try awaitCompatiblePermissions(Array(arguments.dropFirst()))
        case "settings":
            try runSettings(Array(arguments.dropFirst()))
        case "edit":
            try awaitCompatibleEdit(Array(arguments.dropFirst()))
        case "annotations":
            try runAnnotations(Array(arguments.dropFirst()))
        case "transcript":
            try runTranscript(Array(arguments.dropFirst()))
        case "chapters":
            try runChapters(Array(arguments.dropFirst()))
        case "render":
            try awaitCompatibleRender(Array(arguments.dropFirst()))
        case "export":
            try runExport(Array(arguments.dropFirst()))
        case "templates":
            try runTemplates(Array(arguments.dropFirst()))
        case "presets":
            try runPresets(Array(arguments.dropFirst()))
        case "learnhouse":
            try runLearnHouse(Array(arguments.dropFirst()))
        case "share":
            try runShare(Array(arguments.dropFirst()))
        case "connectors":
            try runConnectors(Array(arguments.dropFirst()))
        case "config":
            try runConfig(Array(arguments.dropFirst()))
        case "agent":
            try runAgent(Array(arguments.dropFirst()))
        case "app":
            try runApp(Array(arguments.dropFirst()))
        default:
            throw CLIError.invalidCommand(command)
        }
    }

    static func runProject(_ arguments: [String]) throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("Usage: dmlesson project create|inspect|repair|attach|extract-assets <project> [options] [--json]")
        }

        switch subcommand {
        case "create":
            guard let output = optionValue("--output", in: arguments),
                  let lessonTitle = optionValue("--lesson-title", in: arguments) else {
                throw CLIError.usage("Usage: dmlesson project create --output <project.dmlm> --lesson-title <title> [--course-title <title>] [--template <id>] [--json]")
            }
            let templateID = optionValue("--template", in: arguments) ?? "workshop-lesson"
            guard let template = LessonTemplateLibrary.template(id: templateID) else {
                throw CLIError.usage("Unknown template: \(templateID)")
            }
            let outputURL = URL(fileURLWithPath: output)
            let manifest = template.seedManifest(
                lessonTitle: lessonTitle,
                courseTitle: optionValue("--course-title", in: arguments)
            )
            try ProjectBundle.writeManifest(manifest, to: outputURL)
            if arguments.contains("--json") {
                try printJSON(try ProjectBundle.inspect(at: outputURL))
            } else {
                print("Created project: \(outputURL.path)")
            }
        case "inspect":
            guard arguments.count >= 2 else {
                throw CLIError.usage("Usage: dmlesson project inspect <project> [--json]")
            }
            let projectURL = URL(fileURLWithPath: arguments[1])
            let summary = try ProjectBundle.inspect(at: projectURL)
            if arguments.contains("--json") {
                try printJSON(summary)
            } else {
                print("Project: \(summary.lessonTitle)")
                print("Path: \(summary.urlPath)")
                print("Schema: \(summary.schemaVersion)")
                print("Files: \(summary.fileCount)")
                print("Markers: \(summary.markerCount)")
                print("Issues: \(summary.issues.count)")
            }
        case "repair":
            guard arguments.count >= 2 else {
                throw CLIError.usage("Usage: dmlesson project repair <project> [--lesson-title <title>] [--json]")
            }
            let projectURL = URL(fileURLWithPath: arguments[1])
            let result = try ProjectBundle.repair(
                at: projectURL,
                lessonTitle: optionValue("--lesson-title", in: arguments)
            )
            if arguments.contains("--json") {
                try printJSON(result)
            } else {
                print(result.wroteManifest ? "Recovered project manifest: \(projectURL.path)" : "Project manifest already exists: \(projectURL.path)")
                print("Recovered files: \(result.recoveredFiles.count)")
                print("Issues: \(result.issues.count)")
            }
        case "attach":
            guard arguments.count >= 2 else {
                throw CLIError.usage("Usage: dmlesson project attach <project> [sidecar options] [--json]")
            }
            let projectURL = URL(fileURLWithPath: arguments[1])
            let updated = try ProjectBundle.updateManifest(at: projectURL) { manifest in
                try attachSidecars(from: arguments, projectURL: projectURL, manifest: &manifest)
            }
            if arguments.contains("--json") {
                try printJSON(updated)
            } else {
                print("Updated project manifest: \(projectURL.path)")
            }
        case "extract-assets":
            guard arguments.count >= 2, let output = optionValue("--output", in: arguments) else {
                throw CLIError.usage("Usage: dmlesson project extract-assets <project> --output <directory> [--json]")
            }
            let projectURL = URL(fileURLWithPath: arguments[1])
            let result = try RawAssetExtractor().extract(
                projectURL: projectURL,
                outputDirectory: URL(fileURLWithPath: output, isDirectory: true)
            )
            if arguments.contains("--json") {
                try printJSON(result)
            } else {
                print("Raw assets: \(result.outputDirectoryPath)")
                print("Files: \(result.files.count)")
            }
        default:
            throw CLIError.invalidCommand(subcommand)
        }
    }

    static func awaitCompatibleRecord(_ arguments: [String]) throws {
        let semaphore = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable {
            var result: Result<Void, Error>?
        }
        let box = Box()

        Task {
            do {
                try await runRecord(arguments)
                box.result = .success(())
            } catch {
                box.result = .failure(error)
            }
            semaphore.signal()
        }

        semaphore.wait()
        try box.result?.get()
    }

    static func awaitCompatibleEdit(_ arguments: [String]) throws {
        let semaphore = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable {
            var result: Result<Void, Error>?
        }
        let box = Box()

        Task {
            do {
                try await runEdit(arguments)
                box.result = .success(())
            } catch {
                box.result = .failure(error)
            }
            semaphore.signal()
        }

        semaphore.wait()
        try box.result?.get()
    }

    static func awaitCompatiblePermissions(_ arguments: [String]) throws {
        let semaphore = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable {
            var result: Result<Void, Error>?
        }
        let box = Box()

        Task {
            do {
                try await runPermissions(arguments)
                box.result = .success(())
            } catch {
                box.result = .failure(error)
            }
            semaphore.signal()
        }

        semaphore.wait()
        try box.result?.get()
    }

    static func awaitCompatibleRender(_ arguments: [String]) throws {
        let semaphore = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable {
            var result: Result<Void, Error>?
        }
        let box = Box()

        Task {
            do {
                try await runRender(arguments)
                box.result = .success(())
            } catch {
                box.result = .failure(error)
            }
            semaphore.signal()
        }

        semaphore.wait()
        try box.result?.get()
    }

    static func runRecord(_ arguments: [String]) async throws {
        guard let mode = arguments.first else {
            throw CLIError.usage("Usage: dmlesson record display|region|window|windows|project ...")
        }

        if mode == "windows" || mode == "list-windows" {
            try runWindowListing(Array(arguments.dropFirst()))
            return
        }
        if mode == "project" {
            try await runProjectRecording(Array(arguments.dropFirst()))
            return
        }
        if mode == "microphone" {
            try await runMicrophoneRecording(Array(arguments.dropFirst()))
            return
        }
        if mode == "webcam" {
            try await runWebcamRecording(Array(arguments.dropFirst()))
            return
        }

        guard arguments.count >= 4, ["display", "region", "window"].contains(mode) else {
            throw CLIError.usage("Usage: dmlesson record display|region|window --duration <seconds> --output <screen.mp4> [--system-audio] [--display-id <id>] [--window-id <id>] [--x <points> --y <points> --width <points> --height <points>] [--json]")
        }
        guard let durationValue = optionValue("--duration", in: arguments),
              let duration = TimeInterval(durationValue),
              let output = optionValue("--output", in: arguments) else {
            throw CLIError.usage("Usage: dmlesson record display|region|window --duration <seconds> --output <screen.mp4> [--system-audio] [--display-id <id>] [--window-id <id>] [--x <points> --y <points> --width <points> --height <points>] [--json]")
        }

        let displayID = optionValue("--display-id", in: arguments).flatMap { CGDirectDisplayID($0) }
        let sourceRect: CGRect?
        let windowID: UInt32?
        if mode == "region" {
            guard let x = optionValue("--x", in: arguments).flatMap(Double.init),
                  let y = optionValue("--y", in: arguments).flatMap(Double.init),
                  let width = optionValue("--width", in: arguments).flatMap(Double.init),
                  let height = optionValue("--height", in: arguments).flatMap(Double.init) else {
                throw CLIError.usage("Usage: dmlesson record region --duration <seconds> --output <screen.mp4> --x <points> --y <points> --width <points> --height <points> [--display-id <id>] [--json]")
            }
            sourceRect = CGRect(x: x, y: y, width: width, height: height)
            windowID = nil
        } else if mode == "window" {
            windowID = try positiveUInt32Option("--window-id", in: arguments, required: true)
            sourceRect = nil
        } else {
            sourceRect = nil
            windowID = nil
        }

        let result = try await DisplayScreenRecorder().record(
            DisplayRecordingRequest(
                displayID: displayID,
                outputURL: URL(fileURLWithPath: output),
                durationSeconds: duration,
                options: RecordingOptions(captureSystemAudio: arguments.contains("--system-audio")),
                sourceRect: sourceRect,
                windowID: windowID
            )
        )

        if arguments.contains("--json") {
            try printJSON(result)
        } else {
            let label = mode == "window" ? "window" : "screen"
            print("Recorded \(label): \(result.screenVideoURL.path)")
        }
    }

    static func runWindowListing(_ arguments: [String]) throws {
        let windows = WindowCaptureSourceProvider.availableSources()
        if arguments.contains("--json") {
            try printJSON(windows)
            return
        }

        if windows.isEmpty {
            print("No recordable windows found.")
            return
        }

        for window in windows {
            let size = window.sizeLabel.map { " \($0)" } ?? ""
            print("\(window.id)\t\(window.ownerName)\t\(window.title)\(size)")
        }
    }

    static func runMicrophoneRecording(_ arguments: [String]) async throws {
        guard let durationValue = optionValue("--duration", in: arguments),
              let duration = TimeInterval(durationValue),
              let output = optionValue("--output", in: arguments) else {
            throw CLIError.usage("Usage: dmlesson record microphone --duration <seconds> --output <audio.caf|audio.m4a|audio.wav> [--format caf|m4a|wav] [--microphone-device-id <id>] [--json]")
        }

        let outputURL = URL(fileURLWithPath: output)
        let format = try audioFormat(explicit: optionValue("--format", in: arguments), outputURL: outputURL)
        let result = try await recordMicrophoneFile(
            outputURL: outputURL,
            duration: duration,
            format: format,
            deviceID: optionValue("--microphone-device-id", in: arguments)
        )

        if arguments.contains("--json") {
            try printJSON(result)
        } else {
            print("Recorded microphone: \(result.outputURL.path)")
        }
    }

    static func runWebcamRecording(_ arguments: [String]) async throws {
        guard let durationValue = optionValue("--duration", in: arguments),
              let duration = TimeInterval(durationValue),
              let output = optionValue("--output", in: arguments) else {
            throw CLIError.usage("Usage: dmlesson record webcam --duration <seconds> --output <webcam.mov> [--camera-id <id>] [--resolution 720p|1080p|4K] [--fps 24|30|40|50|60] [--json]")
        }

        let result = try await CameraRecorder().record(
            CameraRecordingRequest(
                outputURL: URL(fileURLWithPath: output),
                durationSeconds: duration,
                deviceID: optionValue("--camera-id", in: arguments),
                resolution: optionValue("--resolution", in: arguments) ?? "1080p",
                fps: try webcamFPSOption("--fps", in: arguments)
            )
        )

        if arguments.contains("--json") {
            try printJSON(result)
        } else {
            print("Recorded webcam: \(result.outputURL.path)")
        }
    }

    static func runProjectRecording(_ arguments: [String]) async throws {
        guard let durationValue = optionValue("--duration", in: arguments),
              let duration = TimeInterval(durationValue),
              let output = optionValue("--output", in: arguments),
              let lessonTitle = optionValue("--lesson-title", in: arguments) else {
            throw CLIError.usage("Usage: dmlesson record project --duration <seconds> --output <project.dmlm> --lesson-title <title> [--course-title <title>] [--region x,y,w,h] [--window-id <id>] [--microphone] [--microphone-device-id <id>] [--webcam] [--camera-fps 24|30|40|50|60] [--webcam-format original|1:1|2:3|3:2|16:9] [--webcam-frame rounded|square|circle] [--mirror-webcam] [--webcam-border] [--system-audio] [--json]")
        }

        let projectURL = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let screenURL = projectURL.appendingPathComponent("screen.mp4")
        let microphoneURL = projectURL.appendingPathComponent("microphone.m4a")
        let webcamURL = projectURL.appendingPathComponent("webcam.mov")
        let sourceRect = optionValue("--region", in: arguments).flatMap(parseRegion)
        let windowID = try positiveUInt32Option("--window-id", in: arguments)
        if sourceRect != nil, windowID != nil {
            throw CLIError.usage("--region and --window-id cannot be used together.")
        }
        let captureSystemAudio = arguments.contains("--system-audio")
        let shouldCaptureMicrophone = arguments.contains("--microphone") || optionValue("--microphone-device-id", in: arguments) != nil
        let shouldCaptureWebcam = arguments.contains("--webcam") || optionValue("--camera-id", in: arguments) != nil
        let cameraResolution = cameraResolutionOption(optionValue("--camera-resolution", in: arguments))
        let cameraFPS = try webcamFPSOption("--camera-fps", in: arguments) ?? 30

        let microphoneTask: Task<AudioRecordingResult, Error>? = shouldCaptureMicrophone
            ? Task {
                try await recordMicrophoneFile(
                    outputURL: microphoneURL,
                    duration: duration,
                    format: .m4a,
                    deviceID: optionValue("--microphone-device-id", in: arguments)
                )
            }
            : nil
        let webcamTask: Task<CameraRecordingResult, Error>? = shouldCaptureWebcam
            ? Task {
                try await CameraRecorder().record(
                    CameraRecordingRequest(
                        outputURL: webcamURL,
                        durationSeconds: duration,
                        deviceID: optionValue("--camera-id", in: arguments),
                        resolution: cameraResolution.rawValue,
                        fps: cameraFPS
                    )
                )
            }
            : nil

        let result = try await DisplayScreenRecorder().record(
            DisplayRecordingRequest(
                outputURL: screenURL,
                durationSeconds: duration,
                options: RecordingOptions(
                    captureSystemAudio: captureSystemAudio,
                    microphoneDeviceID: optionValue("--microphone-device-id", in: arguments),
                    cameraDeviceID: optionValue("--camera-id", in: arguments),
                    cameraResolution: cameraResolution.rawValue
                ),
                sourceRect: sourceRect,
                windowID: windowID
            )
        )
        let microphoneResult = try await microphoneTask?.value
        let webcamResult = try await webcamTask?.value

        let manifest = ProjectManifest(
            metadata: LessonMetadata(
                courseTitle: optionValue("--course-title", in: arguments),
                lessonTitle: lessonTitle
            ),
                media: ProjectMedia(
                    screen: ProjectFile(relativePath: "screen.mp4", role: .screenVideo, mimeType: "video/mp4"),
                    webcam: webcamResult.map { _ in ProjectFile(relativePath: "webcam.mov", role: .webcamVideo, mimeType: "video/quicktime") },
                    microphoneAudio: microphoneResult.map { _ in ProjectFile(relativePath: "microphone.m4a", role: .microphoneAudio, mimeType: "audio/mp4") },
                    embeddedAudio: result.systemAudioURL == nil ? nil : ProjectEmbeddedAudio(screenVideo: [.systemAudio])
                ),
                capture: ProjectCaptureSettings(
                    target: windowID == nil ? (sourceRect == nil ? .screen : .region) : .window,
                    windowID: windowID,
                    region: sourceRect.map(ProjectCaptureRegion.init),
                    screenFPS: 60,
                    includeCursor: true,
                    captureInteractionMetadata: true,
                    captureMicrophone: shouldCaptureMicrophone,
                    microphoneDeviceID: optionValue("--microphone-device-id", in: arguments),
                    captureWebcam: shouldCaptureWebcam,
                    captureSystemAudio: captureSystemAudio,
                    webcam: ProjectWebcamCaptureSettings(
                        cameraID: optionValue("--camera-id", in: arguments),
                        resolution: cameraResolution,
                        fps: cameraFPS,
                        aspectRatio: try webcamAspectRatioOption(optionValue("--webcam-format", in: arguments)),
                        frameShape: try webcamFrameShapeOption(optionValue("--webcam-frame", in: arguments)),
                        cornerRadius: try doubleOption("--webcam-corner-radius", in: arguments) ?? 18,
                        relativeSize: try doubleOption("--webcam-size", in: arguments) ?? 0.24,
                        isMirrored: arguments.contains("--mirror-webcam"),
                        borderEnabled: arguments.contains("--webcam-border"),
                        shadowEnabled: !arguments.contains("--no-webcam-shadow")
                    )
                ),
                tracks: projectTracks(
                    hasWebcam: webcamResult != nil,
                    hasMicrophone: microphoneResult != nil,
                hasSystemAudio: result.systemAudioURL != nil
            ),
            exportPresets: ["learnhouse-1080p"]
        )
        try ProjectBundle.writeManifest(manifest, to: projectURL)

        if arguments.contains("--json") {
            try printJSON(try ProjectBundle.inspect(at: projectURL))
        } else {
            print("Recorded project: \(projectURL.path)")
            print("Screen: \(result.screenVideoURL.path)")
            if let microphoneResult {
                print("Microphone: \(microphoneResult.outputURL.path)")
            }
            if let webcamResult {
                print("Webcam: \(webcamResult.outputURL.path)")
            }
            if result.systemAudioURL != nil {
                print("System audio: embedded in screen.mp4")
            }
        }
    }

    static func runPermissions(_ arguments: [String]) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("Usage: dmlesson permissions status|request-screen|request-microphone|request-camera [--json]")
        }

        switch subcommand {
        case "status":
            let status = CapturePermissionStatus.current()
            if arguments.contains("--json") {
                try printJSON(status)
            } else {
                print("Screen Recording: \(status.screenRecording.granted ? "granted" : "missing")")
                print("Microphone: \(status.microphone.granted ? "granted" : "missing")")
                print("Camera: \(status.camera.granted ? "granted" : "missing")")
            }
        case "request-screen":
            _ = ScreenCapturePermission.requestAccess()
            try printPermissionRequestResult(CapturePermissionStatus.current().screenRecording, json: arguments.contains("--json"))
        case "request-microphone":
            _ = await MicrophonePermission.requestAccess()
            try printPermissionRequestResult(CapturePermissionStatus.current().microphone, json: arguments.contains("--json"))
        case "request-camera":
            _ = await CameraPermission.requestAccess()
            try printPermissionRequestResult(CapturePermissionStatus.current().camera, json: arguments.contains("--json"))
        default:
            throw CLIError.invalidCommand(subcommand)
        }
    }

    static func runSettings(_ arguments: [String]) throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("Usage: dmlesson settings defaults|write-defaults|validate [options] [--json]")
        }

        switch subcommand {
        case "defaults":
            let preferences = LessonMeldPreferences()
            if arguments.contains("--json") {
                try printJSON(preferences)
            } else {
                print("Default project folder: \(preferences.general.defaultProjectDirectory)")
                print("Default template: \(preferences.general.defaultTemplateID)")
                print("Local transcription: \(preferences.transcription.enabled ? "enabled" : "disabled")")
                print("Transcription runtime: \(preferences.transcription.runtime.rawValue)")
                print("Local-only mode: \(preferences.privacy.localOnlyMode)")
                print("LearnHouse enabled: \(preferences.integrations.learnHouseEnabled)")
                print("Agent manifests enabled: \(preferences.integrations.agentManifestsEnabled)")
            }
        case "write-defaults":
            guard let output = optionValue("--output", in: arguments) else {
                throw CLIError.usage("Usage: dmlesson settings write-defaults --output <settings.json>")
            }
            let outputURL = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try DMLessonJSON.encoder().encode(LessonMeldPreferences())
            try data.write(to: outputURL, options: [.atomic])
            if arguments.contains("--json") {
                try printJSON(["output": outputURL.path])
            } else {
                print("Wrote settings defaults: \(outputURL.path)")
            }
        case "validate":
            guard arguments.count >= 2 else {
                throw CLIError.usage("Usage: dmlesson settings validate <settings.json> [--json]")
            }
            let inputURL = URL(fileURLWithPath: arguments[1])
            let data = try Data(contentsOf: inputURL)
            let decoded = try DMLessonJSON.decoder().decode(LessonMeldPreferences.self, from: data)
            let normalized = decoded.normalized()
            if arguments.contains("--json") {
                try printJSON(normalized)
            } else {
                print("Settings valid: \(inputURL.path)")
                if normalized != decoded {
                    print("Normalization would change this file.")
                }
            }
        default:
            throw CLIError.invalidCommand(subcommand)
        }
    }

    static func runEdit(_ arguments: [String]) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("Usage: dmlesson edit plan|decisions|add-cut|add-zoom|validate|export-decisions|export-trim <project.dmlm> [options] [--json]")
        }

        switch subcommand {
        case "decisions":
            guard arguments.count >= 2 else {
                throw CLIError.usage("Usage: dmlesson edit decisions <project.dmlm> [--json]")
            }
            let projectURL = URL(fileURLWithPath: arguments[1])
            let manifest = try ProjectBundle.loadManifest(at: projectURL)
            let editDecisionList = try loadOrCreateEditDecisionList(projectURL: projectURL, manifest: manifest)
            if arguments.contains("--json") {
                try printJSON(editDecisionList)
            } else {
                print("Edit decisions: \(editDecisionList.cuts.count) cuts, \(editDecisionList.zoomRegions.count) zooms, \(editDecisionList.markers.count) markers")
                print("Path: \(EditDecisionListFile.defaultURL(in: projectURL).path)")
            }
        case "add-cut":
            guard arguments.count >= 2,
                  let startValue = optionValue("--start", in: arguments),
                  let endValue = optionValue("--end", in: arguments),
                  let start = TimeInterval(startValue),
                  let end = TimeInterval(endValue),
                  end > start else {
                throw CLIError.usage("Usage: dmlesson edit add-cut <project.dmlm> --start <seconds> --end <seconds> [--reason <text>] [--disabled] [--duration <seconds>] [--json]")
            }
            let projectURL = URL(fileURLWithPath: arguments[1])
            let manifest = try ProjectBundle.loadManifest(at: projectURL)
            var editDecisionList = try loadOrCreateEditDecisionList(projectURL: projectURL, manifest: manifest)
            if let durationValue = optionValue("--duration", in: arguments), let duration = TimeInterval(durationValue) {
                editDecisionList.sourceDurationSeconds = duration
            }
            editDecisionList.cuts.append(TimelineCut(
                id: "cut-\(UUID().uuidString)",
                range: EditTimeRange(startSeconds: start, endSeconds: end),
                reason: optionValue("--reason", in: arguments),
                isEnabled: !arguments.contains("--disabled")
            ))
            let issues = editDecisionList.validate()
            if issues.contains(where: { $0.severity == .error }) {
                if arguments.contains("--json") {
                    try printJSON(issues)
                }
                throw CLIError.usage(issues.map(\.message).joined(separator: " "))
            }
            try EditDecisionListFile.save(editDecisionList, toProject: projectURL)
            if arguments.contains("--json") {
                try printJSON(editDecisionList)
            } else {
                print("Saved cut to \(EditDecisionListFile.defaultURL(in: projectURL).path)")
            }
        case "add-zoom":
            guard arguments.count >= 2,
                  let startValue = optionValue("--start", in: arguments),
                  let endValue = optionValue("--end", in: arguments),
                  let scaleValue = optionValue("--scale", in: arguments),
                  let start = TimeInterval(startValue),
                  let end = TimeInterval(endValue),
                  let scale = Double(scaleValue),
                  end > start else {
                throw CLIError.usage("Usage: dmlesson edit add-zoom <project.dmlm> --start <seconds> --end <seconds> --scale <factor> [--x 0...1] [--y 0...1] [--size 0...1] [--disabled] [--duration <seconds>] [--json]")
            }
            let projectURL = URL(fileURLWithPath: arguments[1])
            let manifest = try ProjectBundle.loadManifest(at: projectURL)
            var editDecisionList = try loadOrCreateEditDecisionList(projectURL: projectURL, manifest: manifest)
            if let durationValue = optionValue("--duration", in: arguments), let duration = TimeInterval(durationValue) {
                editDecisionList.sourceDurationSeconds = duration
            }
            let centerX = Double(optionValue("--x", in: arguments) ?? "0.5") ?? 0.5
            let centerY = Double(optionValue("--y", in: arguments) ?? "0.5") ?? 0.5
            let size = Double(optionValue("--size", in: arguments) ?? "0.5") ?? 0.5
            let clampedSize = min(1, max(0.05, size))
            let halfSize = clampedSize / 2
            let clampedCenterX = min(max(centerX, halfSize), 1 - halfSize)
            let clampedCenterY = min(max(centerY, halfSize), 1 - halfSize)
            editDecisionList.zoomRegions.append(ZoomRegion(
                id: "zoom-\(UUID().uuidString)",
                range: EditTimeRange(startSeconds: start, endSeconds: end),
                focusRect: NormalizedEditRect(
                    x: clampedCenterX - halfSize,
                    y: clampedCenterY - halfSize,
                    width: clampedSize,
                    height: clampedSize
                ),
                scale: scale,
                isEnabled: !arguments.contains("--disabled")
            ))
            let issues = editDecisionList.validate()
            if issues.contains(where: { $0.severity == .error }) {
                if arguments.contains("--json") {
                    try printJSON(issues)
                }
                throw CLIError.usage(issues.map(\.message).joined(separator: " "))
            }
            try EditDecisionListFile.save(editDecisionList, toProject: projectURL)
            if arguments.contains("--json") {
                try printJSON(editDecisionList)
            } else {
                print("Saved zoom region to \(EditDecisionListFile.defaultURL(in: projectURL).path)")
            }
        case "validate":
            guard arguments.count >= 2 else {
                throw CLIError.usage("Usage: dmlesson edit validate <project.dmlm> [--json]")
            }
            let projectURL = URL(fileURLWithPath: arguments[1])
            let manifest = try ProjectBundle.loadManifest(at: projectURL)
            let editDecisionList = try loadOrCreateEditDecisionList(projectURL: projectURL, manifest: manifest)
            let issues = editDecisionList.validate()
            if arguments.contains("--json") {
                try printJSON(issues)
            } else {
                print("Edit decision issues: \(issues.count)")
                for issue in issues {
                    print("\(issue.severity.rawValue): \(issue.path): \(issue.message)")
                }
            }
        case "export-decisions":
            guard arguments.count >= 2,
                  let output = optionValue("--output", in: arguments) else {
                throw CLIError.usage("Usage: dmlesson edit export-decisions <project.dmlm> --output <video.mp4|video.mov> [--duration <seconds>] [--quality passthrough|medium|highest] [--json]")
            }
            let projectURL = URL(fileURLWithPath: arguments[1])
            let manifest = try ProjectBundle.loadManifest(at: projectURL)
            var editDecisionList = try loadOrCreateEditDecisionList(projectURL: projectURL, manifest: manifest)
            if let durationValue = optionValue("--duration", in: arguments), let duration = TimeInterval(durationValue) {
                editDecisionList.sourceDurationSeconds = duration
            }
            let destinationURL = URL(fileURLWithPath: output)
            let plan = try ExportJob(
                id: "edit-decisions-\(UUID().uuidString)",
                editDecisionList: editDecisionList,
                destinationURL: destinationURL,
                preset: editorPreset(from: arguments, outputURL: destinationURL)
            ).makePlan()
            let url = try await AVAssetTrimExportService().export(plan: plan)
            if arguments.contains("--json") {
                try printJSON(["output": url.path])
            } else {
                print("Exported edit decisions: \(url.path)")
            }
        case "plan":
            guard arguments.count >= 2 else {
                throw CLIError.usage("Usage: dmlesson edit plan <project.dmlm> --duration <seconds> [--output <video.mp4>] [--json]")
            }
            guard let durationValue = optionValue("--duration", in: arguments),
                  let duration = TimeInterval(durationValue) else {
                throw CLIError.usage("Usage: dmlesson edit plan <project.dmlm> --duration <seconds> [--output <video.mp4>] [--json]")
            }
            let projectURL = URL(fileURLWithPath: arguments[1])
            let manifest = try ProjectBundle.loadManifest(at: projectURL)
            let sourceURL = try screenMediaURL(projectURL: projectURL, manifest: manifest)
            let destinationURL = URL(fileURLWithPath: optionValue("--output", in: arguments) ?? projectURL.appendingPathComponent("Exports/\(slug(manifest.metadata.lessonTitle)).mp4").path)
            let plan = try ExportJob(
                id: "edit-\(UUID().uuidString)",
                editDecisionList: EditDecisionList(
                    id: "main",
                    sourceMediaURL: sourceURL,
                    sourceDurationSeconds: duration
                ),
                destinationURL: destinationURL,
                preset: editorPreset(from: arguments)
            ).makePlan()
            if arguments.contains("--json") {
                try printJSON(plan)
            } else {
                print("Edit plan: \(manifest.metadata.lessonTitle)")
                print("Source: \(sourceURL.path)")
                print("Destination: \(destinationURL.path)")
            }
        case "export-trim":
            guard arguments.count >= 2,
                  let startValue = optionValue("--start", in: arguments),
                  let endValue = optionValue("--end", in: arguments),
                  let start = TimeInterval(startValue),
                  let end = TimeInterval(endValue),
                  let output = optionValue("--output", in: arguments) else {
                throw CLIError.usage("Usage: dmlesson edit export-trim <project.dmlm> --start <seconds> --end <seconds> --output <video.mp4|video.mov> [--quality passthrough|medium|highest] [--json]")
            }
            let projectURL = URL(fileURLWithPath: arguments[1])
            let manifest = try ProjectBundle.loadManifest(at: projectURL)
            let sourceURL = try screenMediaURL(projectURL: projectURL, manifest: manifest)
            let destinationURL = URL(fileURLWithPath: output)
            let plan = try ExportJob(
                id: "trim-\(UUID().uuidString)",
                editDecisionList: EditDecisionList(
                    id: "main",
                    sourceMediaURL: sourceURL,
                    trimRange: EditTimeRange(startSeconds: start, endSeconds: end)
                ),
                destinationURL: destinationURL,
                preset: editorPreset(from: arguments, outputURL: destinationURL)
            ).makePlan()
            let url = try await AVAssetTrimExportService().export(plan: plan)
            if arguments.contains("--json") {
                try printJSON(["output": url.path])
            } else {
                print("Exported trim: \(url.path)")
            }
        default:
            throw CLIError.invalidCommand(subcommand)
        }
    }

    static func runAnnotations(_ arguments: [String]) throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("Usage: dmlesson annotations init|list|add-text <project.dmlm> [options] [--json]")
        }

        switch subcommand {
        case "init":
            guard arguments.count >= 2 else {
                throw CLIError.usage("Usage: dmlesson annotations init <project.dmlm> [--json]")
            }
            let projectURL = URL(fileURLWithPath: arguments[1])
            let storeURL = projectURL.appendingPathComponent("annotations.json")
            try writeAnnotationStore(AnnotationStore(), to: storeURL)
            let manifest = try attachAnnotationStore(projectURL: projectURL, storeURL: storeURL)
            if arguments.contains("--json") {
                try printJSON(manifest)
            } else {
                print("Initialized annotations: \(storeURL.path)")
            }
        case "list":
            guard arguments.count >= 2 else {
                throw CLIError.usage("Usage: dmlesson annotations list <project.dmlm> [--json]")
            }
            let projectURL = URL(fileURLWithPath: arguments[1])
            let store = try loadAnnotationStore(projectURL: projectURL)
            if arguments.contains("--json") {
                try printJSON(store)
            } else {
                print("Annotations: \(store.annotations.count)")
            }
        case "add-text":
            guard arguments.count >= 2,
                  let text = optionValue("--text", in: arguments) else {
                throw CLIError.usage("Usage: dmlesson annotations add-text <project.dmlm> --text <text> (--x <points> --y <points> | --normalized-x 0...1 --normalized-y 0...1) [--start <seconds>] [--end <seconds>] [--display-id <id>] [--json]")
            }
            let projectURL = URL(fileURLWithPath: arguments[1])
            let storeURL = try annotationStoreURL(projectURL: projectURL, createIfMissing: true)
            var store = try loadAnnotationStore(at: storeURL)
            let displayID = optionValue("--display-id", in: arguments).flatMap(UInt32.init) ?? 0
            let timeRange = try annotationTimeRange(in: arguments)
            let pointPayload = try annotationPointPayload(in: arguments)
            store.add(AnnotationItem(
                displayID: displayID,
                kind: .text,
                points: pointPayload.points,
                normalizedPoints: pointPayload.normalizedPoints,
                coordinateSpace: pointPayload.coordinateSpace,
                timeRange: timeRange,
                color: .yellow,
                text: text,
                textStyle: AnnotationTextStyle()
            ))
            try writeAnnotationStore(store, to: storeURL)
            _ = try attachAnnotationStore(projectURL: projectURL, storeURL: storeURL)
            if arguments.contains("--json") {
                try printJSON(store)
            } else {
                print("Annotations: \(store.annotations.count)")
            }
        default:
            throw CLIError.invalidCommand(subcommand)
        }
    }

    static func runTranscript(_ arguments: [String]) throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("Usage: dmlesson transcript export|model-status [options]")
        }

        switch subcommand {
        case "export":
            guard arguments.count >= 2,
                  let format = optionValue("--format", in: arguments),
                  let output = optionValue("--output", in: arguments) else {
                throw CLIError.usage("Usage: dmlesson transcript export <project.dmlm|transcript.json> --format vtt|srt|md|txt --output <path>")
            }

            let transcript = try loadTranscript(from: URL(fileURLWithPath: arguments[1]))
            let rendered: String
            switch format {
            case "vtt":
                rendered = TranscriptExporter.vtt(transcript)
            case "srt":
                rendered = TranscriptExporter.srt(transcript)
            case "md", "markdown":
                rendered = TranscriptExporter.markdown(transcript)
            case "txt", "text":
                rendered = TranscriptExporter.plainText(transcript)
            default:
                throw CLIError.usage("Unsupported transcript format: \(format)")
            }
            let outputURL = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(rendered.utf8).write(to: outputURL, options: [.atomic])
            if arguments.contains("--json") {
                try printJSON(["output": outputURL.path, "format": format])
            } else {
                print("Transcript exported: \(outputURL.path)")
            }
        case "model-status":
            let preferences = try loadPreferences(from: optionValue("--settings", in: arguments))
            let status = TranscriptionModelInspector.status(for: preferences.transcription)
            if arguments.contains("--json") {
                try printJSON(status)
            } else {
                print("Runtime: \(status.runtime.rawValue)")
                print("Enabled: \(status.enabled ? "yes" : "no")")
                print("Language: \(status.language)")
                print("Model: \(status.expandedModelPath)")
                print("State: \(status.state.rawValue)")
                print(status.message)
            }
        default:
            throw CLIError.invalidCommand(subcommand)
        }
    }

    static func runChapters(_ arguments: [String]) throws {
        guard arguments.count >= 2, arguments[0] == "export" else {
            throw CLIError.usage("Usage: dmlesson chapters export <project.dmlm> --format youtube|md|json --output <path>")
        }
        guard let formatValue = optionValue("--format", in: arguments),
              let output = optionValue("--output", in: arguments) else {
            throw CLIError.usage("Usage: dmlesson chapters export <project.dmlm> --format youtube|md|json --output <path>")
        }

        let format: ChapterExportFormat
        switch formatValue {
        case "youtube":
            format = .youtube
        case "md", "markdown":
            format = .markdown
        case "json":
            format = .json
        default:
            throw CLIError.usage("Unsupported chapter format: \(formatValue)")
        }

        let projectURL = URL(fileURLWithPath: arguments[1])
        let manifest = try ProjectBundle.loadManifest(at: projectURL)
        let entries = ChapterExporter.entries(from: manifest)
        let rendered = try ChapterExporter.render(entries, format: format)
        let outputURL = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(rendered.utf8).write(to: outputURL, options: [.atomic])
        if arguments.contains("--json") {
            try printJSON(["output": outputURL.path, "format": format.rawValue, "chapters": "\(entries.count)"])
        } else {
            print("Chapters exported: \(outputURL.path)")
        }
    }

    static func runRender(_ arguments: [String]) async throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("Usage: dmlesson render plan|export <project.dmlm> --output <video.mp4|video.mov> [--quality medium|highest] [--resolution source|720p|1080p|1440p|4K] [--fps source|24|30|60] [--codec h264|hevc|prores] [--prores] [--json]")
        }
        guard arguments.count >= 2,
              let output = optionValue("--output", in: arguments) else {
            throw CLIError.usage("Usage: dmlesson render \(subcommand) <project.dmlm> --output <video.mp4|video.mov> [--quality medium|highest] [--resolution source|720p|1080p|1440p|4K] [--fps source|24|30|60] [--codec h264|hevc|prores] [--prores] [--json]")
        }

        let projectURL = URL(fileURLWithPath: arguments[1])
        let outputURL = URL(fileURLWithPath: output)
        let preset = renderPreset(from: arguments, outputURL: outputURL)
        let renderer = AVFoundationRenderService()

        switch subcommand {
        case "plan":
            let inspection = try renderer.inspect(
                projectURL: projectURL,
                destinationURL: outputURL,
                preset: preset
            )
            if arguments.contains("--json") {
                try printJSON(inspection)
            } else {
                print("Render plan: \(inspection.lessonTitle)")
                print("Webcam overlay: \(inspection.hasWebcamOverlay ? "yes" : "no")")
                print("Audio sources: \(inspection.audioSourceCount)")
                print("Issues: \(inspection.issues.count)")
            }
        case "export":
            let url = try await renderer.export(
                projectURL: projectURL,
                destinationURL: outputURL,
                preset: preset
            )
            if arguments.contains("--json") {
                try printJSON(["output": url.path])
            } else {
                print("Rendered video: \(url.path)")
            }
        default:
            throw CLIError.invalidCommand(subcommand)
        }
    }

    static func runExport(_ arguments: [String]) throws {
        guard arguments.count >= 3 else {
            throw CLIError.usage("Usage: dmlesson export <project> --preset <id> [--json]")
        }

        let projectURL = URL(fileURLWithPath: arguments[0])
        guard let presetIndex = arguments.firstIndex(of: "--preset"), arguments.indices.contains(presetIndex + 1) else {
            throw CLIError.usage("Usage: dmlesson export <project> --preset <id> [--json]")
        }

        let plan = try ExportPlanner.plan(projectURL: projectURL, presetID: arguments[presetIndex + 1])
        if arguments.contains("--json") {
            try printJSON(plan)
        } else {
            print("Export planned: \(plan.lessonTitle)")
            print("Preset: \(plan.preset.name)")
            print("Status: renderer pending (\(plan.requiredModule))")
        }
    }

    static func runTemplates(_ arguments: [String]) throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("Usage: dmlesson templates list|show <id> [--json]")
        }

        switch subcommand {
        case "apply":
            guard arguments.count >= 2 else {
                throw CLIError.usage("Usage: dmlesson templates apply <id> --lesson-title <title> --output <project> [--course-title <title>] [--json]")
            }
            guard let template = LessonTemplateLibrary.template(id: arguments[1]) else {
                throw CLIError.usage("Unknown template: \(arguments[1])")
            }
            guard let lessonTitle = optionValue("--lesson-title", in: arguments),
                  let output = optionValue("--output", in: arguments) else {
                throw CLIError.usage("Usage: dmlesson templates apply <id> --lesson-title <title> --output <project> [--course-title <title>] [--json]")
            }
            let manifest = template.seedManifest(
                lessonTitle: lessonTitle,
                courseTitle: optionValue("--course-title", in: arguments)
            )
            let outputURL = URL(fileURLWithPath: output)
            try ProjectBundle.writeManifest(manifest, to: outputURL)
            if arguments.contains("--json") {
                try printJSON(try ProjectBundle.inspect(at: outputURL))
            } else {
                print("Created project manifest: \(outputURL.path)")
            }
        case "list":
            if arguments.contains("--json") {
                try printJSON(LessonTemplateLibrary.defaultTemplates)
            } else {
                LessonTemplateLibrary.defaultTemplates.forEach { print("\($0.id)\t\($0.name)") }
            }
        case "show":
            guard arguments.count >= 2, let template = LessonTemplateLibrary.template(id: arguments[1]) else {
                throw CLIError.usage("Usage: dmlesson templates show <id> [--json]")
            }
            if arguments.contains("--json") {
                try printJSON(template)
            } else {
                print("\(template.name): \(template.summary)")
            }
        default:
            throw CLIError.invalidCommand(subcommand)
        }
    }

    static func runPresets(_ arguments: [String]) throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("Usage: dmlesson presets list|show <id>|inspect <preset.dmlpreset>|create-from-project <project> --output <preset.dmlpreset> --name <name>|apply <project> --preset <preset.dmlpreset> [--json]")
        }

        switch subcommand {
        case "list":
            if arguments.contains("--json") {
                try printJSON(LessonTemplateLibrary.defaultExportPresets)
            } else {
                LessonTemplateLibrary.defaultExportPresets.forEach { print("\($0.id)\t\($0.name)") }
            }
        case "show":
            guard arguments.count >= 2, let preset = LessonTemplateLibrary.exportPreset(id: arguments[1]) else {
                throw CLIError.usage("Usage: dmlesson presets show <id> [--json]")
            }
            if arguments.contains("--json") {
                try printJSON(preset)
            } else {
                print("\(preset.name): \(preset.format) \(preset.codec) \(preset.resolution)")
            }
        case "inspect":
            guard arguments.count >= 2 else {
                throw CLIError.usage("Usage: dmlesson presets inspect <preset.dmlpreset> [--json]")
            }
            let preset = try LessonPresetFile.load(from: URL(fileURLWithPath: arguments[1]))
            if arguments.contains("--json") {
                try printJSON(preset)
            } else {
                print("\(preset.name) (\(preset.id))")
                if let summary = preset.summary {
                    print(summary)
                }
                print("Editor settings: \(preset.editorSettings == nil ? "no" : "yes")")
                print("Capture preferences: \(preset.capturePreferences == nil ? "no" : "yes")")
                print("Annotation preferences: \(preset.annotationPreferences == nil ? "no" : "yes")")
                print("Export preferences: \(preset.exportPreferences == nil ? "no" : "yes")")
                print("Export preset IDs: \(preset.exportPresetIDs.isEmpty ? "none" : preset.exportPresetIDs.joined(separator: ", "))")
            }
        case "create-from-project", "export":
            guard arguments.count >= 2,
                  let output = optionValue("--output", in: arguments),
                  let name = optionValue("--name", in: arguments) else {
                throw CLIError.usage("Usage: dmlesson presets create-from-project <project> --output <preset.dmlpreset> --name <name> [--summary <text>] [--settings <settings.json>] [--json]")
            }
            let projectURL = URL(fileURLWithPath: arguments[1])
            let preferences = try optionValue("--settings", in: arguments).map { path in
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                return try DMLessonJSON.decoder().decode(LessonMeldPreferences.self, from: data)
            }
            let preset = try LessonPreset.make(
                fromProject: projectURL,
                preferences: preferences,
                name: name,
                summary: optionValue("--summary", in: arguments)
            )
            let outputURL = normalizedPresetURL(URL(fileURLWithPath: output))
            try LessonPresetFile.save(preset, to: outputURL)
            if arguments.contains("--json") {
                try printJSON(preset)
            } else {
                print("Created preset: \(outputURL.path)")
            }
        case "apply", "import":
            guard arguments.count >= 2, let presetPath = optionValue("--preset", in: arguments) else {
                throw CLIError.usage("Usage: dmlesson presets apply <project> --preset <preset.dmlpreset> [--json]")
            }
            let projectURL = URL(fileURLWithPath: arguments[1])
            let preset = try LessonPresetFile.load(from: URL(fileURLWithPath: presetPath))
            let preview = try LessonPresetApplier.apply(preset, toProject: projectURL)
            if arguments.contains("--json") {
                try printJSON(preview)
            } else {
                print("Applied preset: \(preview.presetName)")
                print("Preserved: \(preview.preservedProjectFields.joined(separator: ", "))")
            }
        case "preview":
            guard arguments.count >= 2, let presetPath = optionValue("--preset", in: arguments) else {
                throw CLIError.usage("Usage: dmlesson presets preview <project> --preset <preset.dmlpreset> [--json]")
            }
            _ = try ProjectBundle.loadManifest(at: URL(fileURLWithPath: arguments[1]))
            let preset = try LessonPresetFile.load(from: URL(fileURLWithPath: presetPath))
            let preview = LessonPresetApplier.preview(preset)
            if arguments.contains("--json") {
                try printJSON(preview)
            } else {
                print("Preset: \(preview.presetName)")
                print("Writes editor settings: \(preview.writesEditorSettings ? "yes" : "no")")
                print("Updates capture settings: \(preview.updatesCaptureSettings ? "yes" : "no")")
                print("Updates export preset IDs: \(preview.updatesExportPresets ? "yes" : "no")")
                print("Preserves: \(preview.preservedProjectFields.joined(separator: ", "))")
            }
        default:
            throw CLIError.invalidCommand(subcommand)
        }
    }

    static func runLearnHouse(_ arguments: [String]) throws {
        guard arguments.count >= 4, arguments[0] == "package" else {
            throw CLIError.usage("Usage: dmlesson learnhouse package <project> --output <directory> [--json]")
        }

        let projectURL = URL(fileURLWithPath: arguments[1])
        guard let outputIndex = arguments.firstIndex(of: "--output"), arguments.indices.contains(outputIndex + 1) else {
            throw CLIError.usage("Usage: dmlesson learnhouse package <project> --output <directory> [--json]")
        }

        let outputURL = URL(fileURLWithPath: arguments[outputIndex + 1])
        let result = try LearnHousePackageBuilder().buildPackage(
            projectURL: projectURL,
            outputDirectory: outputURL,
            archive: arguments.contains("--archive")
        )
        if arguments.contains("--json") {
            try printJSON(result)
        } else {
            print("LearnHouse package: \(result.packagePath)")
            if let archivePath = result.archivePath {
                print("LearnHouse archive: \(archivePath)")
            }
        }
    }

    static func runShare(_ arguments: [String]) throws {
        guard arguments.count >= 4, arguments[0] == "package" else {
            throw CLIError.usage("Usage: dmlesson share package <project> --output <directory> [--final-video <video.mp4|video.mov>] [--archive] [--json]")
        }

        guard let output = optionValue("--output", in: arguments) else {
            throw CLIError.usage("Usage: dmlesson share package <project> --output <directory> [--final-video <video.mp4|video.mov>] [--archive] [--json]")
        }

        let result = try LocalSharePackageBuilder().buildPackage(
            projectURL: URL(fileURLWithPath: arguments[1]),
            outputDirectory: URL(fileURLWithPath: output, isDirectory: true),
            finalVideoURL: optionValue("--final-video", in: arguments).map { URL(fileURLWithPath: $0) },
            archive: arguments.contains("--archive")
        )
        if arguments.contains("--json") {
            try printJSON(result)
        } else {
            print("Share package: \(result.packagePath)")
            if let archivePath = result.archivePath {
                print("Share archive: \(archivePath)")
            }
        }
    }

    static func runConnectors(_ arguments: [String]) throws {
        guard arguments.count >= 5, let output = optionValue("--output", in: arguments) else {
            throw CLIError.usage("Usage: dmlesson connectors common-cartridge|scorm|xapi package <project> --output <directory> [--no-archive] [--json]\n       dmlesson connectors video-host handoff <project> --output <directory> [--archive] [--json]")
        }

        let kind = arguments[0]
        let action = arguments[1]
        let projectURL = URL(fileURLWithPath: arguments[2])
        let outputURL = URL(fileURLWithPath: output, isDirectory: true)
        let result: ConnectorPackageResult
        let label: String

        switch (kind, action) {
        case ("common-cartridge", "package"):
            result = try CommonCartridgePackageBuilder().buildPackage(
                projectURL: projectURL,
                outputDirectory: outputURL,
                archive: !arguments.contains("--no-archive")
            )
            label = "Common Cartridge package"
        case ("scorm", "package"):
            result = try SCORMPackageBuilder().buildPackage(
                projectURL: projectURL,
                outputDirectory: outputURL,
                archive: !arguments.contains("--no-archive")
            )
            label = "SCORM package"
        case ("xapi", "package"):
            result = try XAPIPackageBuilder().buildPackage(
                projectURL: projectURL,
                outputDirectory: outputURL,
                archive: !arguments.contains("--no-archive")
            )
            label = "xAPI package"
        case ("video-host", "handoff"):
            result = try VideoHostHandoffBuilder().buildPackage(
                projectURL: projectURL,
                outputDirectory: outputURL,
                archive: arguments.contains("--archive")
            )
            label = "Video-host handoff"
        default:
            throw CLIError.usage("Usage: dmlesson connectors common-cartridge|scorm|xapi package <project> --output <directory> [--no-archive] [--json]\n       dmlesson connectors video-host handoff <project> --output <directory> [--archive] [--json]")
        }

        if arguments.contains("--json") {
            try printJSON(result)
        } else {
            print("\(label): \(result.packagePath)")
            if let archivePath = result.archivePath {
                print("Archive: \(archivePath)")
            }
        }
    }

    static func runConfig(_ arguments: [String]) throws {
        guard let subcommand = arguments.first, arguments.count >= 2 else {
            throw CLIError.usage("Usage: dmlesson config plan|init|status|commit <config-root> [--message <message>] [--json]")
        }

        let rootURL = URL(fileURLWithPath: arguments[1])
        let manager = ConfigGitBackupManager()

        switch subcommand {
        case "plan":
            let plan = try ConfigBackupPlanner().plan(rootURL: rootURL)
            if arguments.contains("--json") {
                try printJSON(plan)
            } else {
                print("Syncable files: \(plan.includePaths.count)")
                print("Excluded files: \(plan.excludedPaths.count)")
            }
        case "init":
            let status = try manager.ensureRepository(rootURL: rootURL)
            try printConfigStatus(status, json: arguments.contains("--json"))
        case "status":
            let status = try manager.status(rootURL: rootURL)
            try printConfigStatus(status, json: arguments.contains("--json"))
        case "commit":
            guard let message = optionValue("--message", in: arguments) ?? optionValue("-m", in: arguments),
                  !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CLIError.usage("Usage: dmlesson config commit <config-root> --message <message> [--json]")
            }

            let result = try manager.commit(rootURL: rootURL, message: message)
            if arguments.contains("--json") {
                try printJSON(result)
            } else if result.didCommit {
                print("Committed config backup: \(result.commitHash ?? "unknown")")
                print("Files: \(result.committedPaths.count)")
            } else {
                print(result.message)
            }
        default:
            throw CLIError.invalidCommand(subcommand)
        }
    }

    static func runAgent(_ arguments: [String]) throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("Usage: dmlesson agent manifest|workflows [options]")
        }

        switch subcommand {
        case "manifest":
            guard arguments.count >= 2 else {
                throw CLIError.usage("Usage: dmlesson agent manifest <project> [--include-media-paths] [--include-transcript-references] [--json]")
            }
            let options = AgentManifestOptions(
                includeMediaPaths: arguments.contains("--include-media-paths"),
                includeTranscriptReferences: arguments.contains("--include-transcript-references")
            )
            let manifest = try AgentManifestBuilder.build(projectURL: URL(fileURLWithPath: arguments[1]), options: options)
            try printJSON(manifest)
        case "workflows":
            let target = try optionValue("--target", in: arguments).map { rawTarget in
                guard let target = AgentTarget.matching(rawTarget) else {
                    throw CLIError.usage("Unknown agent target: \(rawTarget)")
                }
                return target
            }
            let workflows = AgentWorkflowCatalog.defaultWorkflows(target: target)
            if arguments.contains("--json") {
                try printJSON(workflows)
            } else {
                for workflow in workflows {
                    print("\(workflow.target.rawValue) (\(workflow.targetSlug))")
                    print(workflow.summary)
                    for step in workflow.steps {
                        print("- \(step.command): \(step.purpose)")
                    }
                }
            }
        default:
            throw CLIError.invalidCommand(subcommand)
        }
    }

    static func runApp(_ arguments: [String]) throws {
        guard let subcommand = arguments.first else {
            throw CLIError.usage("Usage: dmlesson app status|show-controls|start|pause|resume|toggle-pause|stop [--json]")
        }

        let action: LocalAppControlAction
        switch subcommand {
        case "status":
            action = .status
        case "show-controls":
            action = .showControls
        case "start":
            action = .start
        case "pause":
            action = .pause
        case "resume":
            action = .resume
        case "toggle-pause":
            action = .togglePause
        case "stop":
            action = .stop
        default:
            throw CLIError.invalidCommand(subcommand)
        }

        if action != .status {
            try postAppControl(action)
            Thread.sleep(forTimeInterval: 0.18)
        }

        let status = (try? LocalAppControl.readStatus()) ?? LocalAppControlStatus(
            pid: 0,
            isAppRunning: false,
            isRecording: false,
            isPaused: false,
            isStopping: false,
            elapsedSeconds: 0,
            lastProjectPath: nil,
            message: "Digital Meld LessonMeld is not reporting runtime status."
        )

        if arguments.contains("--json") {
            try printJSON(status)
        } else if subcommand == "status" {
            print("App: \(status.isAppRunning ? "running" : "not reporting")")
            print("State: \(status.stateLabel)")
            print("Elapsed: \(formatClock(status.elapsedSeconds))")
            if let lastProjectPath = status.lastProjectPath {
                print("Last project: \(lastProjectPath)")
            }
            print("Message: \(status.message)")
        } else {
            print("Sent app command: \(subcommand)")
            print("State: \(status.stateLabel)")
        }
    }

    static func printHelp() {
        print("""
        dmlesson

        Commands:
          project create --output <project.dmlm> --lesson-title <title> [--course-title <title>] [--template <id>] [--json]
          project inspect <project> [--json]
          project repair <project> [--lesson-title <title>] [--json]
          project attach <project> [--screen <path>] [--webcam <path>] [--microphone-audio <path>] [--system-audio <path>] [--cursor-metadata <path>] [--annotations <path>] [--captions <path>] [--transcript <path>] [--thumbnail <path>] [--json]
          project extract-assets <project> --output <directory> [--json]
          permissions status|request-screen|request-microphone|request-camera [--json]
          settings defaults [--json]
          settings write-defaults --output <settings.json> [--json]
          settings validate <settings.json> [--json]
          record display --duration <seconds> --output <screen.mp4> [--display-id <id>] [--system-audio] [--json]
          record region --duration <seconds> --output <screen.mp4> --x <points> --y <points> --width <points> --height <points> [--display-id <id>] [--system-audio] [--json]
          record windows [--json]
          record window --window-id <id> --duration <seconds> --output <screen.mp4> [--system-audio] [--json]
          record microphone --duration <seconds> --output <audio.caf|audio.m4a|audio.wav> [--format caf|m4a|wav] [--microphone-device-id <id>] [--json]
          record webcam --duration <seconds> --output <webcam.mov> [--camera-id <id>] [--resolution 720p|1080p|4K] [--fps 24|30|40|50|60] [--json]
          record project --duration <seconds> --output <project.dmlm> --lesson-title <title> [--course-title <title>] [--region x,y,w,h] [--window-id <id>] [--microphone] [--microphone-device-id <id>] [--webcam] [--camera-resolution 720p|1080p|4K] [--camera-fps 24|30|40|50|60] [--webcam-format original|1:1|2:3|3:2|16:9] [--webcam-frame rounded|square|circle] [--webcam-corner-radius <points>] [--webcam-size 0.10...0.40] [--mirror-webcam] [--webcam-border] [--no-webcam-shadow] [--system-audio] [--json]
          edit decisions|validate <project.dmlm> [--json]
          edit add-cut <project.dmlm> --start <seconds> --end <seconds> [--reason <text>] [--disabled] [--duration <seconds>] [--json]
          edit add-zoom <project.dmlm> --start <seconds> --end <seconds> --scale <factor> [--x 0...1] [--y 0...1] [--size 0...1] [--disabled] [--duration <seconds>] [--json]
          edit plan <project.dmlm> --duration <seconds> [--output <video.mp4>] [--json]
          edit export-decisions <project.dmlm> --output <video.mp4|video.mov> [--duration <seconds>] [--quality passthrough|medium|highest] [--json]
          edit export-trim <project.dmlm> --start <seconds> --end <seconds> --output <video.mp4|video.mov> [--quality passthrough|medium|highest] [--json]
          annotations init|list <project.dmlm> [--json]
          annotations add-text <project.dmlm> --text <text> (--x <points> --y <points> | --normalized-x 0...1 --normalized-y 0...1) [--start <seconds>] [--end <seconds>] [--display-id <id>] [--json]
          transcript export <project.dmlm|transcript.json> --format vtt|srt|md|txt --output <path> [--json]
          transcript model-status [--settings <settings.json>] [--json]
          chapters export <project.dmlm> --format youtube|md|json --output <path> [--json]
          render plan|export <project.dmlm> --output <video.mp4|video.mov> [--quality medium|highest] [--resolution source|720p|1080p|1440p|4K] [--fps source|24|30|60] [--codec h264|hevc|prores] [--concurrency 1...8] [--prores] [--json]
          export <project> --preset <id> [--json]
          templates list|show <id> [--json]
          templates apply <id> --lesson-title <title> --output <project> [--course-title <title>] [--json]
          presets list|show <id>|inspect <preset.dmlpreset> [--json]
          presets create-from-project <project> --output <preset.dmlpreset> --name <name> [--summary <text>] [--settings <settings.json>] [--json]
          presets apply <project> --preset <preset.dmlpreset> [--json]
          learnhouse package <project> --output <directory> [--archive] [--json]
          share package <project> --output <directory> [--final-video <video.mp4|video.mov>] [--archive] [--json]
          connectors common-cartridge|scorm|xapi package <project> --output <directory> [--no-archive] [--json]
          connectors video-host handoff <project> --output <directory> [--archive] [--json]
          config plan|init|status <config-root> [--json]
          config commit <config-root> --message <message> [--json]
          agent manifest <project> [--include-media-paths] [--include-transcript-references]
          agent workflows [--target openclaw|codex|veritas-kanban] [--json]
          app status|show-controls|start|pause|resume|toggle-pause|stop [--json]
        """)
    }

    static func printJSON<T: Encodable>(_ value: T) throws {
        let data = try DMLessonJSON.encoder().encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    static func printPermissionRequestResult(_ permission: CapturePermission, json: Bool) throws {
        if json {
            try printJSON(permission)
        } else {
            print("\(permission.name): \(permission.granted ? "granted" : "missing")")
            if !permission.granted {
                print("Settings: \(permission.settingsURL)")
            }
        }
    }

    static func loadPreferences(from path: String?) throws -> LessonMeldPreferences {
        guard let path else { return LessonMeldPreferences() }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try DMLessonJSON.decoder().decode(LessonMeldPreferences.self, from: data).normalized()
    }

    static func printConfigStatus(_ status: ConfigGitBackupStatus, json: Bool) throws {
        if json {
            try printJSON(status)
        } else {
            print("Repository: \(status.repositoryInitialized ? "initialized" : "not initialized")")
            print("Changed files: \(status.changedPaths.count)")
        }
    }

    static func optionValue(_ option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    static func postAppControl(_ action: LocalAppControlAction) throws {
        let userInfo = try LocalAppControl.controlUserInfo(for: action)
        DistributedNotificationCenter.default().postNotificationName(
            LocalAppControl.notificationName,
            object: LocalAppControl.notificationObject,
            userInfo: userInfo,
            deliverImmediately: true
        )
    }

    static func formatClock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func relativePath(_ path: String, projectURL: URL) -> String {
        let url = URL(fileURLWithPath: path)
        let projectPath = projectURL.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        if filePath.hasPrefix(projectPath + "/") {
            return String(filePath.dropFirst(projectPath.count + 1))
        }
        return path
    }

    static func attachSidecars(from arguments: [String], projectURL: URL, manifest: inout ProjectManifest) throws {
        if let path = optionValue("--screen", in: arguments) {
            manifest.media.screen = try projectFile(path, role: .screenVideo, projectURL: projectURL)
        }
        if let path = optionValue("--webcam", in: arguments) {
            manifest.media.webcam = try projectFile(path, role: .webcamVideo, projectURL: projectURL)
        }
        if let path = optionValue("--microphone-audio", in: arguments) {
            manifest.media.microphoneAudio = try projectFile(path, role: .microphoneAudio, projectURL: projectURL)
        }
        if let path = optionValue("--system-audio", in: arguments) {
            manifest.media.systemAudio = try projectFile(path, role: .systemAudio, projectURL: projectURL)
        }
        if let path = optionValue("--cursor-metadata", in: arguments) {
            manifest.media.cursorMetadata = try projectFile(path, role: .cursorMetadata, projectURL: projectURL)
        }
        if let path = optionValue("--annotations", in: arguments) {
            manifest.media.annotations = try projectFile(path, role: .annotations, projectURL: projectURL)
        }
        if let path = optionValue("--thumbnail", in: arguments) {
            manifest.media.thumbnail = try projectFile(path, role: .thumbnail, projectURL: projectURL)
        }
        if let path = optionValue("--captions", in: arguments) {
            manifest.media.captions.append(try projectFile(path, role: .captions, projectURL: projectURL))
        }
        if let path = optionValue("--transcript", in: arguments) {
            manifest.media.transcripts.append(try projectFile(path, role: .transcript, projectURL: projectURL))
        }
    }

    static func projectFile(_ path: String, role: ProjectFileRole, projectURL: URL) throws -> ProjectFile {
        let file = ProjectFile(
            relativePath: relativePath(path, projectURL: projectURL),
            role: role,
            mimeType: mimeType(for: path)
        )
        _ = try ProjectBundle.projectLocalFileURL(for: file, in: projectURL)
        return file
    }

    static func parseRegion(_ value: String) -> CGRect? {
        let parts = value.split(separator: ",").compactMap { Double(String($0).trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 4 else { return nil }
        return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    static func webcamFPSOption(_ name: String, in arguments: [String]) throws -> Int? {
        guard let value = optionValue(name, in: arguments) else {
            return nil
        }
        guard let fps = Int(value), CapturePreferences.supportedWebcamFPS.contains(fps) else {
            throw CLIError.usage("\(name) must be one of \(CapturePreferences.supportedWebcamFPS.map(String.init).joined(separator: ", ")).")
        }
        return fps
    }

    static func cameraResolutionOption(_ value: String?) -> CameraResolution {
        guard let value else { return .p1080 }
        return CameraResolution(rawValue: value) ?? .p1080
    }

    static func webcamAspectRatioOption(_ value: String?) throws -> WebcamAspectRatio {
        guard let value else { return .widescreen16x9 }
        guard let ratio = WebcamAspectRatio(rawValue: value) else {
            throw CLIError.usage("--webcam-format must be one of original, 1:1, 2:3, 3:2, 16:9.")
        }
        return ratio
    }

    static func webcamFrameShapeOption(_ value: String?) throws -> WebcamFrameShape {
        guard let value else { return .roundedRectangle }
        switch value.lowercased() {
        case "rounded", "rounded-rectangle", "roundedrectangle":
            return .roundedRectangle
        case "square":
            return .square
        case "circle":
            return .circle
        default:
            throw CLIError.usage("--webcam-frame must be one of rounded, square, circle.")
        }
    }

    static func doubleOption(_ name: String, in arguments: [String]) throws -> Double? {
        guard let value = optionValue(name, in: arguments) else { return nil }
        guard let number = Double(value) else {
            throw CLIError.usage("\(name) must be a number.")
        }
        return number
    }

    static func positiveUInt32Option(_ name: String, in arguments: [String], required: Bool = false) throws -> UInt32? {
        guard let value = optionValue(name, in: arguments) else {
            if required {
                throw CLIError.usage("\(name) is required.")
            }
            return nil
        }
        guard let number = UInt32(value), number > 0 else {
            throw CLIError.usage("\(name) must be a positive integer.")
        }
        return number
    }

    struct AnnotationPointPayload {
        var points: [CGPoint]
        var normalizedPoints: [NormalizedAnnotationPoint]?
        var coordinateSpace: AnnotationCoordinateSpace
    }

    static func annotationPointPayload(in arguments: [String]) throws -> AnnotationPointPayload {
        if let normalizedXValue = optionValue("--normalized-x", in: arguments),
           let normalizedYValue = optionValue("--normalized-y", in: arguments),
           let normalizedX = Double(normalizedXValue),
           let normalizedY = Double(normalizedYValue) {
            let normalizedPoint = NormalizedAnnotationPoint(x: normalizedX, y: normalizedY)
            guard normalizedPoint.isValid else {
                throw CLIError.usage("--normalized-x and --normalized-y must be finite values from 0 through 1.")
            }
            return AnnotationPointPayload(
                points: [CGPoint(x: normalizedX, y: normalizedY)],
                normalizedPoints: [normalizedPoint],
                coordinateSpace: .normalizedCapture
            )
        }

        guard let xValue = optionValue("--x", in: arguments),
              let yValue = optionValue("--y", in: arguments),
              let x = Double(xValue),
              let y = Double(yValue) else {
            throw CLIError.usage("Provide either --x <points> --y <points> or --normalized-x 0...1 --normalized-y 0...1.")
        }

        return AnnotationPointPayload(
            points: [CGPoint(x: x, y: y)],
            normalizedPoints: nil,
            coordinateSpace: .legacyCanvasPoints
        )
    }

    static func annotationTimeRange(in arguments: [String]) throws -> AnnotationTimeRange? {
        let startValue = optionValue("--start", in: arguments)
        let endValue = optionValue("--end", in: arguments)
        guard startValue != nil || endValue != nil else { return nil }
        guard let startValue,
              let endValue,
              let start = Double(startValue),
              let end = Double(endValue) else {
            throw CLIError.usage("--start and --end must both be provided as seconds.")
        }
        let range = AnnotationTimeRange(startSeconds: start, endSeconds: end)
        guard range.isValid else {
            throw CLIError.usage("--end must be greater than --start, and both values must be finite non-negative seconds.")
        }
        return range
    }

    static func recordMicrophoneFile(
        outputURL: URL,
        duration: TimeInterval,
        format: AudioFileFormat,
        deviceID: String?
    ) async throws -> AudioRecordingResult {
        let recorder = MicrophoneRecorder()
        let options = AudioRecordingOptions(
            fileFormat: format,
            sampleFormat: format == .m4a ? .aac : .pcmFloat32
        )
        try recorder.startRecording(AudioRecordingRequest(
            source: .microphone(deviceID: deviceID),
            outputURL: outputURL,
            options: options
        ))

        do {
            try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            return try recorder.stopRecording()
        } catch {
            _ = try? recorder.stopRecording()
            throw error
        }
    }

    static func audioFormat(explicit: String?, outputURL: URL) throws -> AudioFileFormat {
        if let explicit {
            guard let format = AudioFileFormat(rawValue: explicit) else {
                throw CLIError.usage("Unsupported audio format: \(explicit)")
            }
            return format
        }
        switch outputURL.pathExtension.lowercased() {
        case "m4a":
            return .m4a
        case "wav":
            return .wav
        default:
            return .caf
        }
    }

    static func projectTracks(hasWebcam: Bool, hasMicrophone: Bool, hasSystemAudio: Bool) -> [TimelineTrack] {
        var tracks = [
            TimelineTrack(id: "screen", kind: .screen, displayName: "Screen")
        ]
        if hasWebcam {
            tracks.append(TimelineTrack(id: "webcam", kind: .webcam, displayName: "Webcam"))
        }
        if hasMicrophone {
            tracks.append(TimelineTrack(id: "microphone", kind: .microphone, displayName: "Microphone"))
        }
        if hasSystemAudio {
            tracks.append(TimelineTrack(id: "system-audio", kind: .systemAudio, displayName: "System Audio (Embedded)"))
        }
        return tracks
    }

    static func screenMediaURL(projectURL: URL, manifest: ProjectManifest) throws -> URL {
        guard let screen = manifest.media.screen else {
            throw CLIError.usage("Project has no screen media.")
        }
        return try ProjectBundle.projectLocalFileURL(for: screen, in: projectURL)
    }

    static func loadOrCreateEditDecisionList(projectURL: URL, manifest: ProjectManifest) throws -> EditDecisionList {
        let sourceMediaURL = try manifest.media.screen.map { try ProjectBundle.projectLocalFileURL(for: $0, in: projectURL) }
        if EditDecisionListFile.exists(in: projectURL) {
            var editDecisionList = try EditDecisionListFile.load(fromProject: projectURL)
            editDecisionList.sourceMediaURL = sourceMediaURL
            return editDecisionList
        }

        return EditDecisionList(
            id: "lesson-edit",
            sourceMediaURL: sourceMediaURL,
            markers: manifest.markers.map { marker in
                TimelineMarker(
                    id: marker.id,
                    kind: editorMarkerKind(for: marker.kind),
                    timeSeconds: marker.timeSeconds,
                    title: marker.title,
                    notes: marker.notes
                )
            }
        )
    }

    static func editorMarkerKind(for kind: ProjectTimelineMarkerKind) -> TimelineMarkerKind {
        switch kind {
        case .chapter:
            .chapter
        case .retake:
            .retake
        case .presenterNote, .segment:
            .note
        }
    }

    static func editorPreset(from arguments: [String], outputURL: URL? = nil) -> ExportPreset {
        let quality = optionValue("--quality", in: arguments).flatMap(ExportQuality.init(rawValue:)) ?? .highest
        let fileType: ExportFileType
        if let outputURL, outputURL.pathExtension.lowercased() == "mov" {
            fileType = .mov
        } else {
            fileType = .mp4
        }
        return ExportPreset(id: "local-\(quality.rawValue)", fileType: fileType, quality: quality)
    }

    static func renderPreset(from arguments: [String], outputURL: URL) -> RenderPreset {
        let quality = optionValue("--quality", in: arguments).flatMap(RenderQuality.init(rawValue:)) ?? .highest
        let fileType: RenderFileType = outputURL.pathExtension.lowercased() == "mov" ? .mov : .mp4
        let codec = arguments.contains("--prores")
            ? RenderCodec.proRes
            : optionValue("--codec", in: arguments).flatMap(RenderCodec.init(rawValue:)) ?? .h264
        return RenderPreset(
            fileType: fileType,
            quality: quality,
            resolution: optionValue("--resolution", in: arguments).flatMap(RenderResolution.init(rawValue:)) ?? .source,
            frameRate: optionValue("--fps", in: arguments).flatMap(RenderFrameRate.init(rawValue:)) ?? .source,
            codec: codec,
            hardwareAccelerationEnabled: !arguments.contains("--disable-hardware-acceleration"),
            maxConcurrentExports: optionValue("--concurrency", in: arguments).flatMap(Int.init) ?? 1,
            alphaChannelEnabled: arguments.contains("--alpha"),
            animatedGIFEnabled: arguments.contains("--gif"),
            proResEnabled: codec == .proRes
        )
    }

    static func normalizedPresetURL(_ url: URL) -> URL {
        url.pathExtension.isEmpty
            ? url.appendingPathExtension(LessonPresetFile.fileExtension)
            : url
    }

    static func annotationStoreURL(projectURL: URL, createIfMissing: Bool) throws -> URL {
        let manifest = try ProjectBundle.loadManifest(at: projectURL)
        if let annotations = manifest.media.annotations {
            return try ProjectBundle.projectLocalFileURL(for: annotations, in: projectURL)
        }
        let url = projectURL.appendingPathComponent("annotations.json")
        if createIfMissing, !FileManager.default.fileExists(atPath: url.path) {
            try writeAnnotationStore(AnnotationStore(), to: url)
        }
        return url
    }

    static func loadAnnotationStore(projectURL: URL) throws -> AnnotationStore {
        try loadAnnotationStore(at: annotationStoreURL(projectURL: projectURL, createIfMissing: false))
    }

    static func loadAnnotationStore(at url: URL) throws -> AnnotationStore {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return AnnotationStore()
        }
        let data = try Data(contentsOf: url)
        return try DMLessonJSON.decoder().decode(AnnotationStore.self, from: data)
    }

    static func loadTranscript(from inputURL: URL) throws -> TranscriptDocument {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: inputURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            let manifest = try ProjectBundle.loadManifest(at: inputURL)
            let file = manifest.media.transcripts.first
                ?? manifest.media.captions.first(where: {
                    $0.mimeType == "application/json" || $0.relativePath.lowercased().hasSuffix(".json")
                })
            guard let file else {
                throw CLIError.usage("Project has no JSON transcript or caption sidecar.")
            }
            let data = try Data(contentsOf: ProjectBundle.projectLocalFileURL(for: file, in: inputURL))
            return try DMLessonJSON.decoder().decode(TranscriptDocument.self, from: data)
        }

        let transcriptData = try Data(contentsOf: inputURL)
        return try DMLessonJSON.decoder().decode(TranscriptDocument.self, from: transcriptData)
    }

    static func writeAnnotationStore(_ store: AnnotationStore, to url: URL) throws {
        try AnnotationSidecarWriter.write(store, to: url)
    }

    static func attachAnnotationStore(projectURL: URL, storeURL: URL) throws -> ProjectManifest {
        try ProjectBundle.updateManifest(at: projectURL) { manifest in
            manifest.media.annotations = try projectFile(storeURL.path, role: .annotations, projectURL: projectURL)
            if !manifest.tracks.contains(where: { $0.id == "annotations" }) {
                manifest.tracks.append(TimelineTrack(id: "annotations", kind: .annotations, displayName: "Annotations"))
            }
        }
    }

    static func slug(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.lowercased().unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let raw = String(scalars)
            .split(separator: "-")
            .joined(separator: "-")
        return raw.isEmpty ? "lesson" : raw
    }

    static func mimeType(for path: String) -> String? {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "mp4": "video/mp4"
        case "mov": "video/quicktime"
        case "jpg", "jpeg": "image/jpeg"
        case "png": "image/png"
        case "m4a": "audio/mp4"
        case "wav": "audio/wav"
        case "vtt": "text/vtt"
        case "srt": "application/x-subrip"
        case "md": "text/markdown"
        case "txt": "text/plain"
        case "json": "application/json"
        default: nil
        }
    }
}

enum CLIError: Error, LocalizedError {
    case invalidCommand(String)
    case usage(String)

    var errorDescription: String? {
        switch self {
        case .invalidCommand(let command):
            "Invalid command: \(command)"
        case .usage(let message):
            message
        }
    }
}

struct CapturePermissionStatus: Codable, Equatable {
    var screenRecording: CapturePermission
    var microphone: CapturePermission
    var camera: CapturePermission

    static func current() -> CapturePermissionStatus {
        CapturePermissionStatus(
            screenRecording: CapturePermission(
                name: "Screen Recording",
                granted: ScreenCapturePermission.isGranted,
                settingsURL: ScreenCapturePermission.privacySettingsURL.absoluteString
            ),
            microphone: CapturePermission(
                name: "Microphone",
                granted: MicrophonePermission.isGranted,
                settingsURL: MicrophonePermission.privacySettingsURL.absoluteString
            ),
            camera: CapturePermission(
                name: "Camera",
                granted: CameraPermission.isGranted,
                settingsURL: CameraPermission.privacySettingsURL.absoluteString
            )
        )
    }
}

struct CapturePermission: Codable, Equatable {
    var name: String
    var granted: Bool
    var settingsURL: String
}
