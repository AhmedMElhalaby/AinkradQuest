import SwiftUI
import AinkradAppKit

struct TimelineSurface: View {
    let document: ProjectDocument
    let theme: HostTheme

    private var layout: TimelineLayout.Result {
        TimelineLayout.build(items: document.items, scheme: document.project.statusScheme)
    }

    var body: some View {
        let result = layout
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if result.bars.isEmpty {
                    Text("Nothing scheduled").foregroundStyle(theme.tokens.foreground.opacity(0.6))
                } else {
                    GeometryReader { geometry in
                        let span = timeSpan(result.bars)
                        ForEach(result.bars) { bar in
                            let x = offset(bar.start, span: span, width: geometry.size.width)
                            let end = offset(bar.end, span: span, width: geometry.size.width)
                            Text(bar.title)
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .frame(width: max(end - x, 60), height: 22, alignment: .leading)
                                .background(theme.tokens.accentPrimary.opacity(0.35))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .offset(x: x, y: CGFloat(bar.lane) * 28)
                        }
                    }
                    .frame(height: CGFloat((result.bars.map(\.lane).max() ?? 0) + 1) * 28)
                }

                if !result.unscheduled.isEmpty {
                    Text("Unscheduled").font(.headline).foregroundStyle(theme.tokens.accentSecondary)
                    ForEach(result.unscheduled) { Text($0.title) }
                }
            }
            .padding(16)
            .foregroundStyle(theme.tokens.foreground)
        }
    }

    private func timeSpan(_ bars: [TimelineBar]) -> (start: Date, end: Date) {
        let start = bars.map(\.start).min() ?? Date()
        let end = bars.map(\.end).max() ?? start.addingTimeInterval(86_400)
        return (start, max(end, start.addingTimeInterval(86_400)))
    }

    private func offset(_ date: Date, span: (start: Date, end: Date), width: CGFloat) -> CGFloat {
        let total = span.end.timeIntervalSince(span.start)
        guard total > 0 else { return 0 }
        return width * CGFloat(date.timeIntervalSince(span.start) / total)
    }
}
