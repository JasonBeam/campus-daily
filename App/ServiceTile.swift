import SwiftUI

struct ServiceTile: View {
    let title: String
    let symbol: String
    let status: String
    let detail: String
    let color: Color
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            HStack(alignment:.top) {
                Image(systemName:symbol).font(.title2).foregroundStyle(color)
                    .frame(width:44,height:44).background(color.opacity(0.10),in:RoundedRectangle(cornerRadius:14))
                Spacer(minLength:4)
                Image(systemName:"arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary).padding(.top,5)
            }
            VStack(alignment:.leading,spacing:7) {
                Text(title).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
            Text(status).font(.caption.weight(.medium)).foregroundStyle(color)
                .padding(.horizontal,9).padding(.vertical,6).background(color.opacity(0.08),in:Capsule())
        }.padding(18).frame(maxWidth:.infinity,alignment:.leading)
            .background(Color(uiColor:.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:24))
            .contentShape(RoundedRectangle(cornerRadius:24)).accessibilityElement(children:.combine)
    }
}
