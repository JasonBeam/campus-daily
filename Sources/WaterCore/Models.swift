import Foundation

public enum WaterError: String, Error, LocalizedError {
    case invalidConfig = "个人配置不完整或格式不正确"
    case busy = "正在处理上一项操作，请稍候"
    case unresolved = "有未确认或未结算的记录，已阻止再次开水"
    case noSession = "没有本 App 创建的待结束记录"
    case wrongDevice = "水控编号不匹配，操作已停止"
    case malformedFrame = "水控回复格式异常，操作未确认"
    case notActive = "水控未返回使用中状态，未发送结束指令"
    case provider = "服务器未确认成功，请先核对校园热水记录"
    case networkUncertain = "网络结果未确认，请勿重复提交；先核对校园热水记录"
    case storage = "无法安全保存操作记录，已阻止后续操作"
    case bluetooth = "蓝牙连接失败，请靠近水控并退出其他水控连接页面"
    case bluetoothOff = "请打开蓝牙并允许本 App 使用蓝牙"
    case targetNotFound = "未找到唯一的目标水控，请靠近后重试"
    case targetMissing = "未发现目标水控，请靠近设备并退出其他水控连接页面"
    case targetAmbiguous = "发现多个同名水控，尚无法确认目标设备"
    case timedOut = "设备回复超时；若已有授权，请先查看当前记录"
    case interrupted = "操作已中断，保留当前记录"
    public var errorDescription: String? { rawValue }
}

public struct WaterConfig: Codable, Equatable, Sendable {
    public let baseURL: String
    public let secret: String
    public let sid: String
    public let studentID: String
    public let schoolID: String
    public let machineID: String
    public let bleName: String
    public let typeID: Int
    public let version: Int
    public let access: WaterAccessSession?
    enum CodingKeys: String, CodingKey {
        case baseURL = "base_url", secret, sid, studentID = "student_id"
        case schoolID = "school_id", machineID = "machine_id", bleName = "ble_name"
        case typeID = "type_id", version, access
    }
    public init(baseURL: String = "https://isv.lxt6.cn", secret: String, sid: String,
                studentID: String, schoolID: String, machineID: String, bleName: String,
                typeID: Int, version: Int, access: WaterAccessSession? = nil) {
        self.baseURL = baseURL; self.secret = secret; self.sid = sid
        self.studentID = studentID; self.schoolID = schoolID
        self.machineID = machineID; self.bleName = bleName
        self.typeID = typeID; self.version = version
        self.access = access
    }
    public func validate() throws {
        let identifier = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.")
        let ids = [studentID, schoolID]
        if let access {try access.validate();guard access.studentID == studentID, access.schoolID == schoolID else {throw WaterError.invalidConfig}}
        guard baseURL == "https://isv.lxt6.cn", access != nil || (!secret.isEmpty && secret.utf8.count <= 256 && !sid.isEmpty && sid.utf8.count <= 128),
              ids.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 64 && $0.unicodeScalars.allSatisfy(identifier.contains) }),
              let machine = Data(strictHex: machineID), machine.count == 4,
              !bleName.isEmpty, bleName.utf8.count <= 64,
              typeID >= 0, version > 0 else { throw WaterError.invalidConfig }
    }
}

public enum SessionStage: String, Codable, Sendable {
    case authorizationPending, authorizationIssued, authorizationWritePending, active
    case closeWritePending, settlementPending, settled
    public var mayClose: Bool { self == .active || self == .authorizationWritePending }
    public var label: String {
        switch self {
        case .authorizationPending: return "授权请求待核对"
        case .authorizationIssued: return "已取得授权，尚未确认写入"
        case .authorizationWritePending: return "授权写入待核对"
        case .active: return "已授权，请按设备出水键"
        case .closeWritePending: return "结束指令待核对"
        case .settlementPending: return "已收到结束数据，结算待核对"
        case .settled: return "服务器已确认结算"
        }
    }
}

public struct WaterSession: Codable, Equatable, Sendable {
    public var stage: SessionStage
    public let machineID: String
    public let peripheralID: String
    public var authorizationID: String?
    public var consumption: Data?
    public let startedAt: Date
    public var endedAt: Date?
    public var receipt: SettlementReceipt?
    public init(stage: SessionStage, machineID: String, peripheralID: String) {
        self.stage = stage; self.machineID = machineID; self.peripheralID = peripheralID
        startedAt = Date()
    }
}

public struct SettlementReceipt: Codable, Equatable, Sendable {
    public let payFen: Int64?
    public var amountYuan: Decimal? { payFen.map { Decimal($0) / 100 } }
    public init(payFen: Int64?) { self.payFen = payFen }
    public static func parse(_ body: [String:Any]) -> SettlementReceipt {
        // Original pay page renders payData.pay / 100 as yuan. No balance-delta guesses.
        let text: String?
        if let number = body["pay"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            text = number.stringValue
        } else { text = body["pay"] as? String }
        guard let text, text.range(of:"^[0-9]+$",options:.regularExpression) != nil,
              let value = Int64(text), value <= 100_000_000_000 else { return SettlementReceipt(payFen:nil) }
        return SettlementReceipt(payFen:value)
    }
}

public struct Authorization: Sendable {
    public let machineID: String
    public let payload: Data
    public let studentID: String
    public init(machineID: String, payload: Data, studentID: String) {
        self.machineID = machineID; self.payload = payload; self.studentID = studentID
    }
}

public extension Data {
    init?(strictHex: String) {
        let bytes = Array(strictHex.utf8)
        guard !bytes.isEmpty, bytes.count % 2 == 0 else { return nil }
        func nibble(_ b: UInt8) -> UInt8? {
            switch b { case 48...57: return b - 48; case 65...70: return b - 55
            case 97...102: return b - 87; default: return nil }
        }
        var result = Data()
        for i in stride(from: 0, to: bytes.count, by: 2) {
            guard let a = nibble(bytes[i]), let b = nibble(bytes[i+1]) else { return nil }
            result.append(a * 16 + b)
        }
        self = result
    }
    var upperHex: String { map { String(format: "%02X", $0) }.joined() }
}
