import Foundation
import WaterCore

@MainActor enum LocalOrderHistoryStore {
    static var issue:String?
    private static var root:URL { FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("LocalOrderHistory",isDirectory:true) }
    static func record(_ value:LocalOrderRecord?, onlyIfMissing:Bool=false) {
        guard let value else { return }
        do {
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication])
            var directory=root;var flags=URLResourceValues();flags.isExcludedFromBackup=true;try directory.setResourceValues(flags)
            let url=root.appendingPathComponent(value.id + ".json")
            if onlyIfMissing && FileManager.default.fileExists(atPath:url.path) {return}
            let data=try JSONEncoder().encode(value)
            if (try? Data(contentsOf:url)) != data {
                try data.write(to:url,options:[.atomic,.completeFileProtectionUntilFirstUserAuthentication])
            }
        } catch { issue="部分本机历史记录未能保存，请保留当前订单并稍后重试。" }
    }
    static func load(owners:[String:String]) throws -> [LocalOrderRecord] {
        guard FileManager.default.fileExists(atPath:root.path) else {return []}
        let files=try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).filter{$0.pathExtension == "json"}
        var values:[LocalOrderRecord]=[]
        for file in files {
            do { values.append(try JSONDecoder().decode(LocalOrderRecord.self,from:Data(contentsOf:file))) }
            catch { issue="部分本机历史记录无法读取，列表可能不完整。" }
        }
        return LocalOrderRecord.recent(values,owners:owners)
    }
}
