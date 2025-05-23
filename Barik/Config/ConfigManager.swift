import Foundation
import SwiftUI
import TOMLDecoder

final class ConfigManager: ObservableObject {
    static let shared = ConfigManager()

    @Published private(set) var config = Config()
    @Published private(set) var initError: String?
    @Published var customFileContent: String = "Loading..." // New property
    
    private var fileWatchSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    private var configFilePath: String?
    
    private var customFileWatchSource: DispatchSourceFileSystemObject? // For custom file
    private var customFileDescriptor: CInt = -1 // For custom file
    private var customStatusFilePath: String? // Path to your custom file


    private init() {
        loadOrCreateConfigIfNeeded()
        setupCustomStatusFile()
    }
    
    private func setupCustomStatusFile() {
           let homePath = FileManager.default.homeDirectoryForCurrentUser.path
           // Define the path to your custom status file
           // For now, let's hardcode it. Later you could make this configurable via barik-config.toml
           let path = "\(homePath)/.config/skhd/scripts/active_mode" // Or read from main config
           self.customStatusFilePath = path

           if !FileManager.default.fileExists(atPath: path) {
               // Create an empty file or default content if it doesn't exist
               do {
                   try "default".write(toFile: path, atomically: true, encoding: .utf8)
                   print("Created default custom status file at \(path)")
               } catch {
                   print("Error creating custom status file: \(error)")
                   DispatchQueue.main.async {
                       self.customFileContent = "Error: No file"
                   }
                   return
               }
           }
           loadCustomFileContent(at: path)
           startWatchingCustomFile(at: path)
       }

    private func loadCustomFileContent(at path: String) {
            do {
                let content = try String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async {
                    self.customFileContent = content.isEmpty ? "Empty" : content
                }
            } catch {
                DispatchQueue.main.async {
                    self.customFileContent = "Error reading file"
                }
                print("Error reading custom status file: \(error)")
            }
        }

        private func startWatchingCustomFile(at path: String) {
            // Close existing watcher if any
            if customFileDescriptor != -1 {
                customFileWatchSource?.cancel()
                close(customFileDescriptor)
                customFileDescriptor = -1
            }

            customFileDescriptor = open(path, O_EVTONLY)
            if customFileDescriptor == -1 {
                print("Error: Could not open custom status file for watching at \(path)")
                DispatchQueue.main.async {
                    self.customFileContent = "Watch Error"
                }
                return
            }

            customFileWatchSource = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: customFileDescriptor,
                eventMask: [.write, .delete, .rename], // Watch for more events
                queue: DispatchQueue.global()
            )

            customFileWatchSource?.setEventHandler { [weak self] in
                guard let self = self, let watchedPath = self.customStatusFilePath else { return }
                // Check if file still exists
                if !FileManager.default.fileExists(atPath: watchedPath) {
                    DispatchQueue.main.async {
                        self.customFileContent = "File Deleted"
                    }
                     // Optionally, try to re-establish watch or handle deletion
                    self.customFileWatchSource?.cancel() // Stop watching if deleted
                    if self.customFileDescriptor != -1 {
                        close(self.customFileDescriptor)
                        self.customFileDescriptor = -1
                    }
                    // Attempt to re-setup (might lead to loops if file is rapidly deleted/recreated)
                    // self.setupCustomStatusFile()
                    return
                }
                self.loadCustomFileContent(at: watchedPath)
            }

            customFileWatchSource?.setCancelHandler { [weak self] in
                if let fd = self?.customFileDescriptor, fd != -1 {
                    close(fd)
                    self?.customFileDescriptor = -1
                }
            }
            customFileWatchSource?.resume()
        }
    
    private func loadOrCreateConfigIfNeeded() {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let path1 = "\(homePath)/.barik-config.toml"
        let path2 = "\(homePath)/.config/barik/config.toml"
        var chosenPath: String?

        if FileManager.default.fileExists(atPath: path1) {
            chosenPath = path1
        } else if FileManager.default.fileExists(atPath: path2) {
            chosenPath = path2
        } else {
            do {
                try createDefaultConfig(at: path1)
                chosenPath = path1
            } catch {
                initError = "Error creating default config: \(error.localizedDescription)"
                print("Error when creating default config:", error)
                return
            }
        }

        if let path = chosenPath {
            configFilePath = path
            parseConfigFile(at: path)
            startWatchingFile(at: path)
        }
    }

    private func parseConfigFile(at path: String) {
        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            let decoder = TOMLDecoder()
            let rootToml = try decoder.decode(RootToml.self, from: content)
            DispatchQueue.main.async {
                self.config = Config(rootToml: rootToml)
            }
        } catch {
            initError = "Error parsing TOML file: \(error.localizedDescription)"
            print("Error when parsing TOML file:", error)
        }
    }

    private func createDefaultConfig(at path: String) throws {
        let defaultTOML = """
            # If you installed yabai or aerospace without using Homebrew,
            # manually set the path to the binary. For example:
            #
            # yabai.path = "/run/current-system/sw/bin/yabai"
            # aerospace.path = ...
            
            theme = "system" # system, light, dark

            [widgets]
            displayed = [ # widgets on menu bar
                "default.spaces",
                "spacer",
                "custom.file_status",
                "default.network",
                "default.battery",
                "divider",
                # { "default.time" = { time-zone = "America/Los_Angeles", format = "E d, hh:mm" } },
                "default.time"
            ]

            [widgets.default.spaces]
            space.show-key = true        # show space number (or character, if you use AeroSpace)
            window.show-title = true
            window.title.max-length = 50

            [widgets.default.battery]
            show-percentage = true
            warning-level = 30
            critical-level = 10

            [widgets.default.time]
            format = "E d, J:mm"
            calendar.format = "J:mm"

            calendar.show-events = true
            # calendar.allow-list = ["Home", "Personal"] # show only these calendars
            # calendar.deny-list = ["Work", "Boss"] # show all calendars except these

            [popup.default.time]
            view-variant = "box"
            
            [background]
            enabled = true
            """
        try defaultTOML.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func startWatchingFile(at path: String) {
        fileDescriptor = open(path, O_EVTONLY)
        if fileDescriptor == -1 { return }
        fileWatchSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor, eventMask: .write,
            queue: DispatchQueue.global())
        fileWatchSource?.setEventHandler { [weak self] in
            guard let self = self, let path = self.configFilePath else {
                return
            }
            self.parseConfigFile(at: path)
        }
        fileWatchSource?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd != -1 {
                close(fd)
            }
        }
        fileWatchSource?.resume()
    }

    func updateConfigValue(key: String, newValue: String) {
        guard let path = configFilePath else {
            print("Config file path is not set")
            return
        }
        do {
            let currentText = try String(contentsOfFile: path, encoding: .utf8)
            let updatedText = updatedTOMLString(
                original: currentText, key: key, newValue: newValue)
            try updatedText.write(
                toFile: path, atomically: false, encoding: .utf8)
            DispatchQueue.main.async {
                self.parseConfigFile(at: path)
            }
        } catch {
            print("Error updating config:", error)
        }
    }

    private func updatedTOMLString(
        original: String, key: String, newValue: String
    ) -> String {
        if key.contains(".") {
            let components = key.split(separator: ".").map(String.init)
            guard components.count >= 2 else {
                return original
            }

            let tablePath = components.dropLast().joined(separator: ".")
            let actualKey = components.last!

            let tableHeader = "[\(tablePath)]"
            let lines = original.components(separatedBy: "\n")
            var newLines: [String] = []
            var insideTargetTable = false
            var updatedKey = false
            var foundTable = false

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                    if insideTargetTable && !updatedKey {
                        newLines.append("\(actualKey) = \"\(newValue)\"")
                        updatedKey = true
                    }
                    if trimmed == tableHeader {
                        foundTable = true
                        insideTargetTable = true
                    } else {
                        insideTargetTable = false
                    }
                    newLines.append(line)
                } else {
                    if insideTargetTable && !updatedKey {
                        let pattern =
                            "^\(NSRegularExpression.escapedPattern(for: actualKey))\\s*="
                        if line.range(of: pattern, options: .regularExpression)
                            != nil
                        {
                            newLines.append("\(actualKey) = \"\(newValue)\"")
                            updatedKey = true
                            continue
                        }
                    }
                    newLines.append(line)
                }
            }

            if foundTable && insideTargetTable && !updatedKey {
                newLines.append("\(actualKey) = \"\(newValue)\"")
            }

            if !foundTable {
                newLines.append("")
                newLines.append("[\(tablePath)]")
                newLines.append("\(actualKey) = \"\(newValue)\"")
            }
            return newLines.joined(separator: "\n")
        } else {
            let lines = original.components(separatedBy: "\n")
            var newLines: [String] = []
            var updatedAtLeastOnce = false

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.hasPrefix("#") {
                    let pattern =
                        "^\(NSRegularExpression.escapedPattern(for: key))\\s*="
                    if line.range(of: pattern, options: .regularExpression)
                        != nil
                    {
                        newLines.append("\(key) = \"\(newValue)\"")
                        updatedAtLeastOnce = true
                        continue
                    }
                }
                newLines.append(line)
            }
            if !updatedAtLeastOnce {
                newLines.append("\(key) = \"\(newValue)\"")
            }
            return newLines.joined(separator: "\n")
        }
    }

    func globalWidgetConfig(for widgetId: String) -> ConfigData {
        config.rootToml.widgets.config(for: widgetId) ?? [:]
    }

    func resolvedWidgetConfig(for item: TomlWidgetItem) -> ConfigData {
        let global = globalWidgetConfig(for: item.id)
        if item.inlineParams.isEmpty {
            return global
        }
        var merged = global
        for (key, value) in item.inlineParams {
            merged[key] = value
        }
        return merged
    }
}
