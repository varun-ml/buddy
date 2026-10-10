import SwiftUI

// MARK: the inbox at the top of the Work tab: every event today, so a bubble you missed is never gone.
// New ones (since the card last closed) show as rows; the rest sit behind "Inbox · N today". Click a row: same as its bubble.

struct NoticeList: View {
    @ObservedObject var m: Model
    var fg: Color = .primary, dim: Color = .secondary   // Ink is dark whatever the system says, so it passes its own
    @State private var all = false

    func list(_ rows: [Bubble]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { b in
                Button { b.action?() } label: {
                    HStack(spacing: 8) {
                        Circle().fill(b.at > m.noticesSeenAt ? b.tone.color : Color.clear).frame(width: 6, height: 6)
                        Text(b.text.components(separatedBy: "\n").first ?? b.text).font(.system(size: 12)).foregroundColor(fg).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(ago(Date().timeIntervalSince(b.at))).font(.system(size: 11)).foregroundColor(dim)
                    }.padding(.vertical, 4).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }

    var body: some View {
        let fresh = m.notices.filter { $0.at > m.noticesSeenAt }
        let rows = all ? m.notices : Array(fresh.prefix(3))
        if !m.notices.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Button { all.toggle() } label: {
                    Text(all ? "Inbox · hide" : "Inbox · \(fresh.isEmpty ? "" : "\(fresh.count) new · ")\(m.notices.count) today \(all ? "▴" : "▾")")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(dim)
                }.buttonStyle(.plain)
                if all { ScrollView { list(rows) }.frame(maxHeight: 240) } else { list(rows) }   // plain list when short: renders anywhere
            }.padding(.bottom, 8)
        }
    }
}
