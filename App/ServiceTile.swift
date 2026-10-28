import SwiftUI

struct ServiceTile: View {
    let title: String
    let symbol: String
    let status: String
    let detail: String
    let color: Color
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Image(systemName:symbol).font(.title2).foregroundStyle(NativeTheme.tint)
                .accessibilityHidden(true)
            VStack(alignment:.leading,spacing:6) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            HStack(alignment:.firstTextBaseline,spacing:6) {
                Text(status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                Spacer(minLength:0)
                Image(systemName:"arrow.up.right").font(.caption).foregroundStyle(NativeTheme.tint).accessibilityHidden(true)
            }
        }.padding(18).frame(maxWidth:.infinity,alignment:.leading)
            .background(NativeTheme.surface,in:RoundedRectangle(cornerRadius:NativeTheme.radius))
            .contentShape(RoundedRectangle(cornerRadius:NativeTheme.radius)).accessibilityElement(children:.combine)
    }
}
