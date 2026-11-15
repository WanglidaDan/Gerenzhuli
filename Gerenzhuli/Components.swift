import SwiftUI

// MARK: - 共用小组件（严格按精修规范：小字号、发丝线、圆角 12–14）

/// 分组标题：13pt medium，灰色
struct GZSectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title)
                .font(.gzSubhead)
                .foregroundStyle(Color.gzSecondary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.gzCaption)
                    .foregroundStyle(Color.gzSecondary)
            }
        }
        .padding(.horizontal, 4)
    }
}

/// 状态小圆点 / 小标签
struct GZStatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

/// 提醒时间线节点：四种状态长相
struct TimelineNode: View {
    let status: ReminderStatus
    let size: CGFloat = 26

    var body: some View {
        ZStack {
            switch status {
            case .done:
                Circle().fill(Color.gzGreen)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            case .overdue:
                Circle().fill(Color.gzRed)
                Image(systemName: "exclamationmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            case .inProgress:
                Circle().stroke(Color.gzGreen, lineWidth: 1.5)
                Circle().fill(Color.gzGreen).frame(width: 10, height: 10)
            case .upcoming:
                Circle().stroke(Color.gzTertiary, lineWidth: 1.5)
            }
        }
        .frame(width: size, height: size)
        .animation(GZ.spring, value: status)
    }
}

/// 时间线行：左侧节点 + 竖线，右侧标题 + 日期·状态 + 灰色小字
struct TimelineRow: View {
    let title: String
    let meta: String
    let detail: String
    let status: ReminderStatus
    let isLast: Bool
    var onTapNode: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Button(action: { onTapNode?() }) {
                    TimelineNode(status: status)
                }
                .gzPressable()
                .buttonStyle(.plain)
                if !isLast {
                    Rectangle()
                        .fill(Color.gzHairline)
                        .frame(width: 1)
                        .frame(minHeight: 36)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.gzHeadline)
                    .foregroundStyle(Color.gzText)
                Text(meta)
                    .font(.gzFootnote)
                    .foregroundStyle(Color.gzSecondary)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.gzFootnote)
                        .foregroundStyle(Color.gzSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .gzListTransition()
        .gzScrollFade()
    }
}

/// 数字格：三格数字用
struct StatCell: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.gzNumberLarge)
                .foregroundStyle(color)
            Text(label)
                .font(.gzCaption)
                .foregroundStyle(Color.gzSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}
