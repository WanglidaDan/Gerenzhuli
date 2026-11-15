import SwiftData
import SwiftUI

// MARK: - 流媒体订阅
// 15 位台账种子，月收入由订阅行实时加总；k 已过期 2026-11-12 置顶；
// 按 Netflix / HBO Max / Disney+ 筛选；每位一行：名字、资料、到期日、价格、状态。
// 不存、不显示订阅的真实电话号码。

enum SubscriberFilter: String, CaseIterable {
    case all, netflix, hbo, disney

    var title: String {
        switch self {
        case .all: return "全部"
        case .netflix: return "Netflix"
        case .hbo: return "HBO Max"
        case .disney: return "Disney+"
        }
    }

    var platform: Platform? {
        switch self {
        case .all: return nil
        case .netflix: return .netflix
        case .hbo: return .hbo
        case .disney: return .disney
        }
    }
}

struct SubscribersView: View {
    @Query(sort: \Subscriber.expiry) private var subscribers: [Subscriber]
    @State private var filter: SubscriberFilter = .all

    private var filtered: [Subscriber] {
        guard let platform = filter.platform else { return subscribers }
        return subscribers.filter { $0.platform == platform }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // 汇总卡
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(Store.monthlyTotal(from: subscribers).cny)
                                .font(.gzNumberLarge)
                                .foregroundStyle(Color.gzText)
                            Text("/ 月")
                                .font(.gzFootnote)
                                .foregroundStyle(Color.gzSecondary)
                            Spacer()
                            Text("\(subscribers.count) 位")
                                .font(.gzFootnote)
                                .foregroundStyle(Color.gzSecondary)
                        }
                        HStack(spacing: 14) {
                            ForEach(Store.monthlySplit(from: subscribers), id: \.0) { platform, amount in
                                HStack(spacing: 4) {
                                    Circle().fill(platform.color).frame(width: 7, height: 7)
                                    Text("\(platform.shortTitle) \(amount.cny)")
                                        .font(.gzFootnote)
                                        .foregroundStyle(Color.gzSecondary)
                                }
                            }
                        }
                    }
                    .padding(14)
                    .gzCardStyle()

                    // 筛选
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(SubscriberFilter.allCases, id: \.self) { f in
                                Button {
                                    withAnimation(GZ.spring) { filter = f }
                                } label: {
                                    Text(f.title)
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .foregroundStyle(filter == f ? .white : Color.gzText)
                                        .padding(.horizontal, 13)
                                        .padding(.vertical, 7)
                                        .background(filter == f ? Color.gzInkGreen2 : Color.gzCard)
                                        .clipShape(Capsule())
                                }
                                .gzPressable()
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // 订阅列表：一行一位
                    VStack(spacing: 0) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { index, sub in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(sub.platform.color.opacity(0.14))
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Text(String(sub.name.prefix(1)))
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(sub.platform.color)
                                    )
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(sub.name)
                                            .font(.gzHeadline)
                                            .foregroundStyle(Color.gzText)
                                            .lineLimit(1)
                                        GZStatusPill(text: sub.status.title, color: sub.status.color)
                                    }
                                    Text("\(sub.platform.title) · \(sub.profile) · 到期 \(sub.expiryText)")
                                        .font(.gzFootnote)
                                        .foregroundStyle(Color.gzSecondary)
                                        .lineLimit(1)
                                    if !sub.note.isEmpty {
                                        Text(sub.note)
                                            .font(.gzCaption)
                                            .foregroundStyle(Color.gzSecondary)
                                    }
                                }
                                Spacer()
                                Text(sub.billingLabel)
                                    .font(.gzFootnote)
                                    .foregroundStyle(Color.gzText)
                                    .multilineTextAlignment(.trailing)
                            }
                            .padding(.vertical, 10)
                            .gzListTransition()
                            .gzScrollFade()
                            if index < filtered.count - 1 {
                                Divider().padding(.leading, 46)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .gzCardStyle()
                    .gzListTransition()
                    .animation(GZ.spring, value: filtered.map(\.id))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color.gzBackground)
            .navigationTitle("流媒体订阅")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}
