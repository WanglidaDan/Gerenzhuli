import SwiftData
import SwiftUI

// MARK: - 早报详情页
// 定版格式：标题「M月D日早报 · 昨日M月D日要闻」，国内 / 国际 / 财经 / 科技四节、
// 连续编号，每项 = 编号 + 加粗关键词 + 一句话 + 来源，10–14 项。
// 内容一律用占位「待生成」，不编造新闻；真实早报由定时任务生成后替换种子。

struct BriefingView: View {
    @Query(sort: \BriefingItem.order) private var items: [BriefingItem]
    @Environment(\.dismiss) private var dismiss

    private var today: Date { Date() }
    private var yesterday: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    }

    private var titleText: String {
        "\(today.gzMonthDay)早报 · 昨日\(yesterday.gzMonthDay)要闻"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(titleText)
                            .font(.gzTitle)
                            .foregroundStyle(Color.gzText)
                        Text("每天 08:10 更新")
                            .font(.gzFootnote)
                            .foregroundStyle(Color.gzSecondary)
                    }
                    .padding(.top, 4)
                    .gzAppear(delay: 0)

                    ForEach(Array(BriefingSection.allCases.enumerated()), id: \.element) { sectionIndex, section in
                        let rows = items.filter { $0.section == section }
                        if !rows.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                GZSectionHeader(title: section.title)
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(Array(rows.enumerated()), id: \.element.id) { _, item in
                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                                Text("\(item.order)")
                                                    .font(.gzNumber)
                                                    .foregroundStyle(Color.gzInkGreen2)
                                                    .frame(width: 20, alignment: .trailing)
                                                Text(item.keyword)
                                                    .font(.system(size: 13.5, weight: .semibold))
                                                    .foregroundStyle(Color.gzText)
                                            }
                                            Text(item.summary)
                                                .font(.gzFootnote)
                                                .foregroundStyle(Color.gzSecondary)
                                                .padding(.leading, 26)
                                            Text(item.source)
                                                .font(.gzCaption)
                                                .foregroundStyle(Color.gzTertiary)
                                                .padding(.leading, 26)
                                        }
                                        .padding(.vertical, 8)
                                        if item.id != rows.last?.id {
                                            Divider().padding(.leading, 26)
                                        }
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 4)
                                .gzCardStyle()
                            }
                            .gzAppear(delay: 0.06 + Double(sectionIndex) * 0.06)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Color.gzBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
