import Foundation

/// `Application Support/Water/`, where an imported `.waterconfig` is written. It holds the
/// platform secret, so it is kept out of backups.
public enum ShowerImportFolder {
    public static func url(in applicationSupport: URL) -> URL {
        applicationSupport.appendingPathComponent("Water", isDirectory: true)
    }

    /// Creates the folder of `file` and keeps it out of backups, before the file is written.
    public static func prepare(for file: URL, fileManager: FileManager = .default) throws {
        let folder = file.deletingLastPathComponent()
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try excludeFromBackup(folder)
    }

    static func excludeFromBackup(_ folder: URL) throws {
        var url = folder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}
