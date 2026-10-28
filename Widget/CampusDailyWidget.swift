import SwiftUI
import WidgetKit
import WaterCore

struct CampusEntry: TimelineEntry { let date: Date; let snapshot: CampusSnapshot? }
struct CampusTimeline: TimelineProvider {
    func placeholder(in context: Context) -> CampusEntry { CampusEntry(date:Date(),snapshot:nil) }
    func getSnapshot(in context: Context, completion: @escaping (CampusEntry) -> Void) {
        completion(CampusEntry(date:Date(),snapshot:CampusSharedCache.read(CampusSnapshot.self)))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CampusEntry>) -> Void) {
        Task { @MainActor in
            var cached = CampusSharedCache.read(CampusSnapshot.self)
            if let config = CampusSharedCache.config(), (try? config.validate()) != nil {
                if cached?.owner != config.cacheIdentity { cached = nil }
                var next = cached ?? CampusSnapshot(owner:config.cacheIdentity)
                let provider = CampusProvider()
                if next.balanceIsStale() {
                    do { next.recordBalance(.success(try await provider.balance(config:config))) }
                    catch { next.recordBalance(.failure((error as? CampusError) ?? .network)) }
                }
                if !config.buildingID.isEmpty, next.powerIsStale() {
                    do { next.recordPower(.success(try await provider.electricity(config:config))) }
                    catch { next.recordPower(.failure((error as? CampusError) ?? .network)) }
                }
                if CampusSharedCache.config()?.cacheIdentity == config.cacheIdentity {
                    try? CampusSharedCache.save(next); cached = next
                } else { cached = CampusSharedCache.read(CampusSnapshot.self) }
            }
            completion(Timeline(entries:[CampusEntry(date:Date(),snapshot:cached)],policy:.after(Date().addingTimeInterval(1200))))
        }
    }
}

/// Port of Scriptable's existing 170 x 170 POWER / CARD composition.
struct ScriptsCampusFace: View {
    let snapshot: CampusSnapshot?
    private func number(_ value: Decimal?, places: Int = 2) -> String {
        guard let value else { return "—" }
        return NSDecimalNumber(decimal:value).stringValue
    }
    var body: some View {
        GeometryReader { geometry in
            Canvas { context,size in
                let sx = size.width / 170, sy = size.height / 170
                context.scaleBy(x:sx,y:sy)
                let ink = Color(red:0.08,green:0.08,blue:0.08)
                let muted = Color(red:0.35,green:0.35,blue:0.33)
                func text(_ value: String,_ x: CGFloat,_ y: CGFloat,_ size: CGFloat = 10.67,_ display: Bool = false,_ right: Bool = false,_ width: CGFloat = 142) {
                    let font: Font = display ? .custom("Doto-Black_Regular",size:size) : .custom("SpaceMono-Regular",size:size)
                    let resolved = context.resolve(Text(value).font(font).foregroundStyle(display ? ink : muted))
                    let measured = resolved.measure(in:CGSize(width:1000,height:100))
                    let scale = min(1,width / max(1,measured.width))
                    var drawing = context
                    drawing.translateBy(x:right ? x - measured.width * scale : x,y:y)
                    drawing.scaleBy(x:scale,y:scale)
                    drawing.draw(resolved,at:.zero,anchor:.topLeading)
                }
                func line(_ x: CGFloat,_ y: CGFloat,_ w: CGFloat,_ h: CGFloat) {
                    context.fill(Path(CGRect(x:x,y:y,width:w,height:h)),with:.color(ink.opacity(0.2)))
                }
                func bar(_ value: Decimal?,_ maximum: Double,_ x: CGFloat,_ width: CGFloat) {
                    let ratio = value.map { max(0,min(1,NSDecimalNumber(decimal:$0).doubleValue / maximum)) } ?? 0
                    context.fill(Path(CGRect(x:x,y:110,width:width,height:3)),with:.color(ink.opacity(0.12)))
                    context.fill(Path(CGRect(x:x,y:110,width:width * ratio,height:3)),with:.color(ink))
                }
                context.stroke(Path(ellipseIn:CGRect(x:14,y:18,width:6,height:6)),with:.color(ink),lineWidth:0.8)
                text("CAMPUS",25,17)
                let stamp = snapshot?.balanceFetchedAt ?? snapshot?.powerFetchedAt
                text(stamp?.formatted(date:.omitted,time:.shortened) ?? "未更新",156,17,10.67,false,true)
                text("POWER",14,39); text("CARD",101,39)
                text(number(snapshot?.electricity?.remainingKWh),14,60,32,true,false,65)
                text(number(snapshot?.balance),101,60,32,true,false,55)
                text("度",14,92); text("元",101,92)
                bar(snapshot?.electricity?.remainingKWh,100,14,65); bar(snapshot?.balance,30,101,55)
                line(90,54,0.67,60); line(14,118,142,0.67)
                text(number(snapshot?.electricity?.yesterdayKWh) + " 度",14,128,10.67,false,false,80)
                text("昨日用电",156,128,10.67,false,true,65)
                text(number(snapshot?.electricity?.balanceYuan) + " 元",14,145,10.67,false,false,80)
                let stale = snapshot?.balanceIsStale() != false || (snapshot?.electricity != nil && snapshot?.powerIsStale() != false)
                text(stale ? "上次查询" : "电费余额",156,145,10.67,false,true,65)
            }
        }.accessibilityElement(children:.ignore)
            .accessibilityLabel("宿舍剩余电量 \(number(snapshot?.electricity?.remainingKWh)) 度，校园卡 \(number(snapshot?.balance)) 元，电费余额 \(number(snapshot?.electricity?.balanceYuan)) 元")
    }
}
@main struct CampusDailyWidget: Widget {
    let kind = "CampusDailyBalances"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind:kind,provider:CampusTimeline()) { entry in
            ScriptsCampusFace(snapshot:entry.snapshot)
                .containerBackground(Color(red:0.96,green:0.957,blue:0.937),for:.widget)
                .widgetURL(URL(string:"campusdaily://balances"))
                .privacySensitive()
        }.configurationDisplayName("校园双余额")
            .description("沿用 Scripts：宿舍电量、校园卡余额、昨日用电和电费余额。更新时间由系统安排。")
            .supportedFamilies([.systemSmall]).contentMarginsDisabled()
    }
}
