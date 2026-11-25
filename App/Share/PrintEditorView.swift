import PhotosUI
import SwiftUI
import RoadPrintCore

/// The Print card editor (Design/cards/print/README.md "Editor concept"): the card over the driver's
/// photo. Hold a block (title, route, elevation, distance) and slide it up or down; it stops at the
/// safe area and at its neighbours. Tap × to hide a block and bring it back from Hidden. Ink is Auto
/// (from the photo), Light or Dark; Full and Sticker are starting layouts.
struct PrintEditorView: View {
    let input: PrintCardInput
    let road: MainRoad?
    /// The backdrop from the share sheet (the sample sky or the driver's photo); nil for none.
    var initialPhoto: UIImage?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var photo: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var inkChoice: InkChoice = .auto
    @State private var mode: PrintLayoutMode = .full
    @State private var arrangement = PrintArrangement.standard
    @State private var selected: PrintBlock?
    @State private var drag: DragState?
    @State private var exported: URL?

    enum InkChoice: String, CaseIterable, Identifiable {
        case auto, light, dark
        var id: String { rawValue }
        var name: String {
            switch self {
            case .auto: String(localized: "Auto", comment: "Print editor: pick the ink from the photo.")
            case .light: String(localized: "Light", comment: "Print editor: white type for dark photos.")
            case .dark: String(localized: "Dark", comment: "Print editor: dark type for bright photos.")
            }
        }
    }

    private struct DragState {
        let block: PrintBlock
        let start: PrintArrangement
        let layout: PrintCardLayout
    }

    private typealias M = ShareCardMetrics
    private static let pxPerPoint = CardTokens.Print.Export.width / M.size.width

    private var ink: PrintInk {
        switch inkChoice {
        case .light: .light
        case .dark: .dark
        case .auto: photo.map { PrintInkChooser.ink(for: $0) } ?? .light
        }
    }

    private var layout: PrintCardLayout {
        PrintCard.layout(input, ink: ink, mode: mode, arrangement: arrangement, measurer: CoreTextMeasurer.shared)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: RPSpace.m) {
                canvas
                controls
            }
            .padding(.horizontal, RPSpace.screenMargin)
            .padding(.bottom, RPSpace.m)
            .background(Color.RP.Night.background.ignoresSafeArea())
            .navigationTitle(Text("Edit card", comment: "Print editor title."))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let exported {
                        ShareLink(item: exported) { Text("Share") }
                            .accessibilityIdentifier("printEditorShare")
                    } else {
                        ProgressView()
                    }
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .onAppear { if photo == nil { photo = initialPhoto } }
        .onChange(of: pickerItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    photo = image
                }
            }
        }
        .task(id: ExportKey(ink: ink, mode: mode, arrangement: arrangement, hasPhoto: photo != nil)) {
            await export()
        }
    }

    private struct ExportKey: Equatable {
        let ink: PrintInk
        let mode: PrintLayoutMode
        let arrangement: PrintArrangement
        let hasPhoto: Bool
    }

    // MARK: Canvas

    private var canvas: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / M.size.width, proxy.size.height / M.size.height)
            let layout = self.layout
            ZStack(alignment: .topLeading) {
                (photo == nil ? Color.RP.Night.land : Color.clear)
                PrintCardView(layout: layout, road: road, photo: photo)
                selection(layout)
            }
            .frame(width: M.size.width, height: M.size.height, alignment: .topLeading)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: M.size.width * scale, height: M.size.height * scale, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: RPRadius.card))
            .contentShape(Rectangle())
            .gesture(dragGesture(scale: scale, layout: layout))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("printEditorCanvas")
        }
    }

    /// The chosen block: a dashed outline, a handle on the right and × on the left when it may hide.
    @ViewBuilder
    private func selection(_ layout: PrintCardLayout) -> some View {
        if let selected, let range = layout.blocks[selected] {
            let top = range.lowerBound / Self.pxPerPoint - 6, height = (range.upperBound - range.lowerBound) / Self.pxPerPoint + 12
            RoundedRectangle(cornerRadius: RPSpace.s)
                .strokeBorder(Color.RP.Night.route, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .background(Color.RP.Night.route.opacity(0.06), in: RoundedRectangle(cornerRadius: RPSpace.s))
                .frame(width: M.size.width - 24, height: height)
                .offset(x: 12, y: top)
                .allowsHitTesting(false)
            Capsule()
                .fill(Color.RP.Night.route)
                .frame(width: 10, height: 36)
                .offset(x: M.size.width - 17, y: top + height / 2 - 18)
                .allowsHitTesting(false)
            if PrintCard.canHide(selected, in: arrangement) {
                Button {
                    arrangement.hidden.insert(selected)
                    self.selected = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.rpText(size: 9, weight: .bold))
                        .foregroundStyle(Color.RP.Night.text)
                        .frame(width: 22, height: 22)
                        .background(Color.RP.Night.background, in: Circle())
                        .overlay(Circle().strokeBorder(Color.RP.Night.route, lineWidth: 1.5))
                }
                .offset(x: 1, y: top - 11)
                .accessibilityLabel(Text("Hide \(Self.name(selected))", comment: "Print editor: hide a block; the placeholder is its name."))
                .accessibilityIdentifier("printEditorHide")
            }
        }
    }

    private func dragGesture(scale: CGFloat, layout: PrintCardLayout) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if drag == nil {
                    let y = value.startLocation.y / scale * Self.pxPerPoint
                    guard let block = layout.blocks.first(where: { $0.value.contains(y) })?.key else {
                        selected = nil
                        return
                    }
                    selected = block
                    drag = DragState(block: block, start: arrangement, layout: layout)
                }
                guard let drag else { return }
                let dy = value.translation.height / scale * Self.pxPerPoint
                arrangement = PrintCard.move(drag.block, by: dy, in: drag.start, layout: drag.layout)
            }
            .onEnded { _ in drag = nil }
    }

    // MARK: Controls

    private var controls: some View {
        // The picker label closure is Sendable: give it a value, not the state.
        let hasPhoto = photo != nil
        return VStack(alignment: .leading, spacing: RPSpace.s) {
            HStack {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(!hasPhoto ? String(localized: "Add photo", comment: "Print editor: choose a background photo.")
                                       : String(localized: "Change photo", comment: "Print editor: choose another background photo."),
                          systemImage: "photo")
                }
                .accessibilityIdentifier("printEditorPhoto")
                if photo != nil {
                    Button(String(localized: "Remove", comment: "Print editor: remove the background photo.")) {
                        photo = nil
                        pickerItem = nil
                    }
                }
            }
            row(String(localized: "Ink", comment: "Print editor: the type colour picker.")) {
                Picker("Ink", selection: $inkChoice) {
                    ForEach(InkChoice.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("printEditorInk")
            }
            row(String(localized: "Layout", comment: "Print editor: the layout picker.")) {
                Picker("Layout", selection: $mode) {
                    Text("Full", comment: "Print editor: the card over the whole photo.").tag(PrintLayoutMode.full)
                    Text("Sticker", comment: "Print editor: the card in the lower part of the photo.").tag(PrintLayoutMode.sticker)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("printEditorLayout")
            }
            .onChange(of: mode) { _, _ in
                arrangement = .standard
                selected = nil
            }
            row(String(localized: "Hidden", comment: "Print editor: blocks the driver hid.")) {
                if arrangement.hidden.isEmpty {
                    Text("Nothing hidden", comment: "Print editor: no hidden blocks.")
                        .font(RPType.statLabel)
                        .foregroundStyle(Color.RP.Night.textSecondary)
                } else {
                    HStack {
                        ForEach(PrintBlock.allCases.filter { arrangement.hidden.contains($0) }, id: \.self) { block in
                            Button {
                                arrangement.hidden.remove(block)
                            } label: {
                                Text("+ \(Self.name(block))", comment: "Print editor: bring back a hidden block.")
                                    .font(RPType.statLabel)
                                    .padding(.horizontal, RPSpace.s)
                                    .frame(height: 30)
                                    .overlay(Capsule().strokeBorder(Color.RP.Night.textSecondary, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                            }
                            .foregroundStyle(Color.RP.Night.text)
                        }
                    }
                }
            }
        }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: RPSpace.m) {
            Text(label)
                .font(RPType.statLabel)
                .textCase(.uppercase)
                .foregroundStyle(Color.RP.Night.textSecondary)
                .frame(width: 64, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    static func name(_ block: PrintBlock) -> String {
        switch block {
        case .header: String(localized: "Title", comment: "Print editor block: wordmark, title and date.")
        case .route: String(localized: "Route", comment: "Print editor block: the route.")
        case .elevation: String(localized: "Elevation", comment: "Print editor block: the elevation strip.")
        case .stats: String(localized: "Distance", comment: "Print editor block: the big number and the stats.")
        }
    }

    // MARK: Export

    /// The card as a 1080 × 1920 PNG: over the photo, or transparent without one.
    @MainActor
    private func export() async {
        exported = nil
        let renderer = ImageRenderer(content: PrintCardView(layout: layout, road: road, photo: photo))
        renderer.scale = M.exportScale
        renderer.isOpaque = photo != nil
        guard let data = renderer.uiImage?.pngData() else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("RoadPrint-print.png")
        do {
            try data.write(to: url, options: .atomic)
            exported = url
        } catch {
            exported = nil
        }
    }
}

/// Picks the ink from a photo: dark type when the photo is bright (mean luminance over the card's
/// lower two thirds above the threshold), light type otherwise. Engineering configuration, not a token.
enum PrintInkChooser {
    /// Measured on the bundled backdrops (ROA-128): night sky 0.13, bright cloud sky 0.50. A bright daylight
    /// photo sits well above 0.35, a night or dusk photo well below.
    static let threshold = 0.35

    static func ink(for photo: UIImage) -> PrintInk {
        luminance(of: photo) > threshold ? .dark : .light
    }

    /// Mean relative luminance of the photo as the card crops it (aspect fill to 9:16), sampled small.
    static func luminance(of photo: UIImage) -> Double {
        guard let cg = photo.cgImage else { return 0 }
        let w = 9, h = 16
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let ok = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            let iw = Double(cg.width), ih = Double(cg.height), k = max(Double(w) / iw, Double(h) / ih)
            let dw = iw * k, dh = ih * k
            context.draw(cg, in: CGRect(x: (Double(w) - dw) / 2, y: (Double(h) - dh) / 2, width: dw, height: dh))
            return true
        }
        guard ok else { return 0 }
        func lin(_ c: UInt8) -> Double { let v = Double(c) / 255; return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        var sum = 0.0, n = 0.0
        // Bitmap memory starts at the image's top row; the card's blocks cover the lower two thirds.
        for y in (h / 3)..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                sum += 0.2126 * lin(pixels[i]) + 0.7152 * lin(pixels[i + 1]) + 0.0722 * lin(pixels[i + 2])
                n += 1
            }
        }
        return n > 0 ? sum / n : 0
    }
}
