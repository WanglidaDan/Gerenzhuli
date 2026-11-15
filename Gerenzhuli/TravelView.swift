import CoreLocation
import MapKit
import PhotosUI
import SwiftData
import SwiftUI

// MARK: - 出行：记行程
// 一次行程 = 出发 + 交通 + 住宿 + 要去的地方，按时间排；机票 / 门票 / 订单挂在行程下面。
// 导航走 MapKit（地名反编码后打开苹果地图）；票证进钱包是占位（待接 PassKit）；
// 行程配图走 Photos（PHPicker，本次会话内展示，不落库）；
// 订票是查价比价 + 下单确认流程占位：只列示例报价、不写死支付、不扣款。

struct TravelView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(Store.self) private var store
    @Query(sort: \Trip.departDate) private var trips: [Trip]

    @State private var expandedID: UUID?
    @State private var showNewTrip = false
    @State private var showWallet: Trip?
    @State private var showBooking: Trip?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GZSectionHeader(title: "行程", trailing: "\(trips.count) 次")
                        .padding(.top, 4)
                    if trips.isEmpty {
                        Text("还没有行程，点右上角加一次。")
                            .font(.gzBody)
                            .foregroundStyle(Color.gzSecondary)
                            .padding(.vertical, 8)
                    }
                    ForEach(trips) { trip in
                        tripCard(trip)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Color.gzBackground)
            .navigationTitle("出行")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNewTrip = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .gzPressable()
                    .accessibilityLabel("新建行程")
                }
            }
            .sheet(isPresented: $showNewTrip) {
                NewTripSheet { trip in store.addTrip(trip, in: modelContext) }
            }
            .sheet(item: $showWallet) { trip in
                WalletSheet(trip: trip)
            }
            .sheet(item: $showBooking) { trip in
                BookingSheet(trip: trip) { ticket in
                    store.addTicket(ticket, to: trip, in: modelContext)
                }
            }
        }
    }

    // MARK: - 行程卡（点卡片在原地展开，不跳页）

    private func tripCard(_ trip: Trip) -> some View {
        let expanded = expandedID == trip.id
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(GZ.spring) {
                    expandedID = expanded ? nil : trip.id
                }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(trip.title)
                            .font(.gzHeadline)
                            .foregroundStyle(Color.gzText)
                        Spacer()
                        GZStatusPill(text: trip.status.title, color: trip.status.color)
                    }
                    Text("\(trip.destination) · \(trip.dateRangeText)")
                        .font(.gzFootnote)
                        .foregroundStyle(Color.gzSecondary)
                    if !trip.transport.isEmpty {
                        Text(trip.transport)
                            .font(.gzFootnote)
                            .foregroundStyle(Color.gzSecondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 4) {
                        Text(expanded ? "收起" : "展开详情")
                            .font(.gzCaption)
                            .foregroundStyle(Color.gzInkGreen2)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.gzInkGreen2)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .padding(.top, 2)
                    .animation(GZ.spring, value: expanded)
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Divider().padding(.horizontal, 14)
                TripDetailView(
                    trip: trip,
                    onNavigate: { openInMaps(destination: trip.destination) },
                    onWallet: { showWallet = trip },
                    onBook: { showBooking = trip }
                )
                .padding(14)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .gzCardStyle()
        .animation(GZ.spring, value: expandedID)
        .gzListTransition()
        .gzScrollFade()
    }

    /// MapKit 导航入口：地名反编码后打开苹果地图；反编码失败时退回地图搜索链接。
    private func openInMaps(destination: String) {
        let query = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        CLGeocoder().geocodeAddressString(query) { placemarks, _ in
            if let placemark = placemarks?.first, let location = placemark.location {
                let item = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
                item.name = query
                item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
            } else if let url = URL(string: "maps://?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)") {
                UIApplication.shared.open(url)
            }
        }
    }
}

// MARK: - 行程详情（在卡片内展开）

private struct TripDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(Store.self) private var store
    let trip: Trip
    var onNavigate: () -> Void
    var onWallet: () -> Void
    var onBook: () -> Void

    @State private var photos: [UIImage] = []
    @State private var showPhotoPicker = false
    @State private var showAddStop = false
    @State private var newStopKind: TripStopKind = .place
    @State private var newStopTitle = ""
    @State private var newStopTime = ""

    private var stops: [TripStop] {
        trip.stops.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 入口行：导航 / 票证 / 配图 / 订票
            HStack(spacing: 8) {
                detailButton(icon: "map.fill", label: "导航", action: onNavigate)
                detailButton(icon: "wallet.pass.fill", label: "票证", action: onWallet)
                detailButton(icon: "photo.fill", label: "配图", action: { showPhotoPicker = true })
                detailButton(icon: "ticket.fill", label: "订票", action: onBook)
            }

            // 行程时间线：出发 / 交通 / 住宿 / 要去的地方
            GZSectionHeader(title: "行程")
            if stops.isEmpty {
                Text("还没排站，点下面加一站。")
                    .font(.gzFootnote)
                    .foregroundStyle(Color.gzSecondary)
            }
            ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                TripStopRow(stop: stop, isLast: index == stops.count - 1)
            }
            Button {
                withAnimation(GZ.spring) { showAddStop.toggle() }
            } label: {
                Label(showAddStop ? "收起" : "加一站", systemImage: "plus.circle.fill")
                    .font(.gzFootnote)
                    .foregroundStyle(Color.gzInkGreen2)
            }
            .gzPressable()
            if showAddStop {
                VStack(spacing: 8) {
                    Picker("类型", selection: $newStopKind) {
                        ForEach(TripStopKind.allCases, id: \.self) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    TextField("这一站去哪 / 做什么", text: $newStopTitle)
                        .font(.gzBody)
                        .textFieldStyle(.roundedBorder)
                    TextField("时间，如 12月5日 10:00", text: $newStopTime)
                        .font(.gzBody)
                        .textFieldStyle(.roundedBorder)
                    Button("加上这一站") {
                        let title = newStopTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !title.isEmpty else { return }
                        let stop = TripStop(kind: newStopKind, title: title,
                                            timeLabel: newStopTime.isEmpty ? "时间待定" : newStopTime,
                                            sortOrder: (stops.map { $0.sortOrder }.max() ?? -1) + 1)
                        modelContext.insert(stop)
                        trip.stops.append(stop)
                        try? modelContext.save()
                        newStopTitle = ""
                        newStopTime = ""
                        showAddStop = false
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.gzInkGreen2)
                    .clipShape(Capsule())
                    .gzPressable()
                }
            }

            // 票 / 订单：挂在行程下面
            GZSectionHeader(title: "票 / 订单")
            if trip.tickets.isEmpty {
                Text("还没有票，点「订票」比价下单。")
                    .font(.gzFootnote)
                    .foregroundStyle(Color.gzSecondary)
            }
            ForEach(trip.tickets) { ticket in
                HStack(spacing: 10) {
                    Image(systemName: ticket.kind.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.gzInkGreen2)
                        .frame(width: 28, height: 28)
                        .background(Color.gzCard2)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ticket.title)
                            .font(.gzBody)
                            .foregroundStyle(Color.gzText)
                        Text("\(ticket.statusText)\(ticket.code.isEmpty ? "" : " · \(ticket.code)")")
                            .font(.gzCaption)
                            .foregroundStyle(Color.gzSecondary)
                    }
                    Spacer()
                    Text(ticket.price.cny)
                        .font(.gzNumber)
                        .foregroundStyle(Color.gzText)
                }
                .padding(.vertical, 2)
            }

            // 配图（本次会话内展示，不落库）
            if !photos.isEmpty {
                GZSectionHeader(title: "配图")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { _, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 84, height: 84)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }

            if !trip.stay.isEmpty {
                Text("住宿：\(trip.stay)")
                    .font(.gzFootnote)
                    .foregroundStyle(Color.gzSecondary)
            }
            if !trip.note.isEmpty {
                Text(trip.note)
                    .font(.gzFootnote)
                    .foregroundStyle(Color.gzSecondary)
            }

            Button(role: .destructive) {
                store.deleteTrip(trip, in: modelContext)
            } label: {
                Text("删除这条行程")
                    .font(.gzFootnote)
            }
            .gzPressable()
        }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPicker(images: $photos)
        }
    }

    private func detailButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.gzInkGreen2)
                Text(label)
                    .font(.gzCaption)
                    .foregroundStyle(Color.gzText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(Color.gzCard2)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .gzPressable()
    }
}

/// 行程里的一站：左侧图标 + 竖线，右侧标题 + 时间 + 小字
private struct TripStopRow: View {
    let stop: TripStop
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Image(systemName: stop.kind.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.gzInkGreen2)
                    .frame(width: 26, height: 26)
                    .background(Color.gzCard2)
                    .clipShape(Circle())
                if !isLast {
                    Rectangle()
                        .fill(Color.gzHairline)
                        .frame(width: 1)
                        .frame(minHeight: 30)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(stop.title)
                    .font(.gzHeadline)
                    .foregroundStyle(Color.gzText)
                Text("\(stop.kind.title) · \(stop.timeLabel)")
                    .font(.gzFootnote)
                    .foregroundStyle(Color.gzSecondary)
                if !stop.detail.isEmpty {
                    Text(stop.detail)
                        .font(.gzFootnote)
                        .foregroundStyle(Color.gzSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 票证：钱包入口占位

private struct WalletSheet: View {
    @Environment(\.dismiss) private var dismiss
    let trip: Trip

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("钱包票证入口占位")
                        .font(.gzTitle)
                        .foregroundStyle(Color.gzText)
                    Text("订票成功后，机票、门票会以票证形式存到钱包，这里直接打开查看。当前是占位：还没接 PassKit，票证先列在行程下面。")
                        .font(.gzBody)
                        .foregroundStyle(Color.gzSecondary)
                    if trip.tickets.isEmpty {
                        Text("这条行程还没有票。")
                            .font(.gzFootnote)
                            .foregroundStyle(Color.gzSecondary)
                    }
                    ForEach(trip.tickets) { ticket in
                        HStack {
                            Image(systemName: ticket.kind.icon)
                                .foregroundStyle(Color.gzInkGreen2)
                            Text(ticket.title)
                                .font(.gzBody)
                            Spacer()
                            GZStatusPill(text: ticket.statusText, color: .gzBlue)
                        }
                        .padding(12)
                        .gzCardStyle()
                    }
                }
                .padding(16)
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

// MARK: - 订票：查价比价 + 下单确认（占位，不写死支付、不扣款）

private struct BookingSheet: View {
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    var onConfirm: (TripTicket) -> Void

    @State private var selectedIndex = 0
    @State private var showConfirm = false

    /// 示例报价：占位数据，不是实时查价。接真实票务接口后替换为接口返回。
    private var options: [(name: String, price: Int, note: String)] {
        [
            ("直销渠道", 1680, "官网直销 · 可退改"),
            ("聚合平台", 1540, "含 20 元券 · 不可退"),
            ("旅行社代订", 1790, "含接送机 · 可退改"),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("订票 · \(trip.destination)")
                        .font(.gzTitle)
                        .foregroundStyle(Color.gzText)
                    Text("先比价，再确认下单。当前是流程占位：价格为示例、未接真实票务接口，不会扣款；确认后生成一张「待出票」的票，挂在这条行程下面。")
                        .font(.gzBody)
                        .foregroundStyle(Color.gzSecondary)
                    GZSectionHeader(title: "比价")
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        Button {
                            withAnimation(GZ.spring) { selectedIndex = index }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.name)
                                        .font(.gzHeadline)
                                        .foregroundStyle(Color.gzText)
                                    Text(option.note)
                                        .font(.gzFootnote)
                                        .foregroundStyle(Color.gzSecondary)
                                }
                                Spacer()
                                Text(option.price.cny)
                                    .font(.gzNumber)
                                    .foregroundStyle(Color.gzText)
                                Image(systemName: selectedIndex == index ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedIndex == index ? Color.gzGreen : Color.gzTertiary)
                            }
                            .padding(12)
                            .gzCardStyle()
                        }
                        .buttonStyle(.plain)
                        .gzPressable()
                    }
                    Button("下单确认") {
                        showConfirm = true
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.gzInkGreen2)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .gzPressable()
                    .padding(.top, 4)
                }
                .padding(16)
            }
            .background(Color.gzBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .alert("确认下单？", isPresented: $showConfirm) {
                Button("确认下单") {
                    let option = options[selectedIndex]
                    onConfirm(TripTicket(kind: .flight, title: "\(trip.destination)机票 · \(option.name)",
                                         price: option.price, statusText: "待出票"))
                    dismiss()
                }
                Button("再想想", role: .cancel) {}
            } message: {
                let option = options[selectedIndex]
                Text("\(option.name) \(option.price.cny)，\(option.note)。占位流程，不会扣款，确认后生成待出票订单。")
            }
        }
    }
}

// MARK: - 新建行程

private struct NewTripSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onSave: (Trip) -> Void

    @State private var title = ""
    @State private var destination = ""
    @State private var departDate = Date()
    @State private var returnDate = Date().addingTimeInterval(2 * 86400)
    @State private var transport = ""
    @State private var stay = ""
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("行程") {
                    TextField("行程名，如 香港三日", text: $title)
                    TextField("目的地", text: $destination)
                    DatePicker("出发", selection: $departDate, displayedComponents: .date)
                    DatePicker("返回", selection: $returnDate, displayedComponents: .date)
                }
                Section("交通住宿") {
                    TextField("交通，如 飞机 / 高铁", text: $transport)
                    TextField("住宿，如 酒店 2 晚", text: $stay)
                    TextField("备注", text: $note)
                }
                Button("保存行程") {
                    let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let dest = destination.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty, !dest.isEmpty else { return }
                    onSave(Trip(title: name, destination: dest, departDate: departDate,
                                returnDate: max(returnDate, departDate),
                                transport: transport, stay: stay, note: note))
                    dismiss()
                }
                .font(.system(size: 15, weight: .semibold))
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .navigationTitle("新建行程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Photos：行程配图（PHPicker，本次会话内展示）

private struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var images: [UIImage]
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 6
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker

        init(_ parent: PhotoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            guard !results.isEmpty else { return }
            for result in results {
                result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                    guard let image = object as? UIImage else { return }
                    Task { @MainActor in
                        self?.parent.images.append(image)
                    }
                }
            }
        }
    }
}
