import PhotosUI
import SwiftUI
import RoadPrintCore

/// The share sheet's style picker (ROA-128, layout B of the board's design study): every style as a
/// small card with its full name, a PRO badge on a locked one, and an amber ring on the chosen one.
struct ShareStyleStrip: View {
    @Binding var selection: ShareCardStyle
    let isLocked: (ShareCardStyle) -> Bool

    var body: some View {
        HStack(alignment: .top, spacing: RPSpace.m) {
            ForEach(ShareCardStyle.allCases) { style in
                ShareStyleThumb(style: style, selected: style == selection, locked: isLocked(style)) {
                    selection = style
                }
            }
        }
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shareStyleStrip")
    }
}

private struct ShareStyleThumb: View {
    let style: ShareCardStyle
    let selected: Bool
    let locked: Bool
    let action: () -> Void

    /// 60 × 107 pt: a 9:16 card, the size of the bundled 180 × 320 thumbnails at 3×.
    static let size = CGSize(width: 60, height: 106.67)

    var body: some View {
        Button(action: action) {
            VStack(spacing: RPSpace.xs + 2) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let image = ShareAssets.thumbnail(style) {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            Color.RP.Night.land
                        }
                    }
                    .frame(width: Self.size.width, height: Self.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: RPSpace.s, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: RPSpace.s, style: .continuous)
                            .strokeBorder(selected ? Color.RP.Night.route : Color.RP.Night.border, lineWidth: selected ? 2.5 : 1)
                            .padding(selected ? -3.5 : 0)
                    }
                    if locked {
                        ProBadge().padding(RPSpace.xs)
                    }
                }
                Text(style.name)
                    .font(.rpText(size: 10.5, weight: selected ? .bold : .medium))
                    .foregroundStyle(selected ? Color.RP.accentText : Color.RP.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(locked ? Text("\(style.name), Pro", comment: "Share sheet: a card style in the strip that needs RoadPrint Pro.")
                                   : Text(verbatim: style.name))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("shareStyle.\(style.rawValue)")
    }
}

/// The small amber PRO capsule.
struct ProBadge: View {
    var body: some View {
        Text(verbatim: "PRO")
            .font(.rpText(size: 7.5, weight: .heavy))
            .tracking(0.6)
            .foregroundStyle(Color.RP.Night.background)
            .padding(.horizontal, 4.5)
            .frame(height: 13)
            .background(Color.RP.Night.route, in: Capsule())
            .accessibilityHidden(true)
    }
}

/// What the Print card sits on in the share sheet. The driver shares what they see: the card over the
/// backdrop, or a transparent sticker for Clear. The ink follows the backdrop (Auto).
enum PrintBackdrop: String, CaseIterable, Identifiable, Sendable {
    case nightSky, brightSky, photo, clear

    var id: String { rawValue }

    var name: String {
        switch self {
        case .nightSky: String(localized: "Night sky", comment: "Share sheet, Print: the sample night photo behind the card.")
        case .brightSky: String(localized: "Bright sky", comment: "Share sheet, Print: the sample bright photo behind the card.")
        case .photo: String(localized: "Your photo", comment: "Share sheet, Print: put the card on one of your photos.")
        case .clear: String(localized: "Clear", comment: "Share sheet, Print: no backdrop; share a transparent sticker.")
        }
    }

    /// The ink for this backdrop: light on the night sky, dark on the bright sky, from the picture for
    /// the driver's photo, and the board's light v2 card for a transparent sticker.
    func ink(photo: UIImage?) -> PrintInk {
        switch self {
        case .nightSky, .clear: .light
        case .brightSky: .dark
        case .photo: photo.map { PrintInkChooser.ink(for: $0) } ?? .light
        }
    }
}

/// Bundled share-sheet pictures (App/Resources/ShareBackdrops, App/Resources/ShareStyles;
/// Tools/design/build_share_assets.py). Loaded once and kept: about 2 MB decoded for the backdrops.
@MainActor
enum ShareAssets {
    private static var cache: [String: UIImage] = [:]

    private static func image(_ name: String) -> UIImage? {
        if let image = cache[name] { return image }
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg"),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache[name] = image
        return image
    }

    static func thumbnail(_ style: ShareCardStyle) -> UIImage? { image(style.rawValue) }
    static var terrainSample: UIImage? { image("terrain-sample") }
    static var nightSky: UIImage? { image("night-sky") }
    static var brightSky: UIImage? { image("bright-sky") }

    static func backdrop(_ backdrop: PrintBackdrop, photo: UIImage?) -> UIImage? {
        switch backdrop {
        case .nightSky: nightSky
        case .brightSky: brightSky
        case .photo: photo
        case .clear: nil
        }
    }
}

/// The row of backdrop chips under the strip when Print is chosen. "Your photo" opens Photos.
struct PrintBackdropRow: View {
    @Binding var backdrop: PrintBackdrop
    @Binding var pickerItem: PhotosPickerItem?
    let hasPhoto: Bool

    var body: some View {
        HStack(spacing: RPSpace.s) {
            ForEach(PrintBackdrop.allCases) { option in
                if option == .photo {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        chip(option, selected: backdrop == .photo && hasPhoto)
                    }
                    .accessibilityAddTraits(backdrop == .photo && hasPhoto ? .isSelected : [])
                    .accessibilityIdentifier("printBackdrop.photo")
                } else {
                    Button {
                        backdrop = option
                    } label: {
                        chip(option, selected: backdrop == option)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(backdrop == option ? .isSelected : [])
                    .accessibilityIdentifier("printBackdrop.\(option.rawValue)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(_ option: PrintBackdrop, selected: Bool) -> some View {
        Text(option.name)
            .font(.rpText(size: 13, weight: .semibold))
            .foregroundStyle(selected ? Color.RP.Night.background : Color.RP.text)
            .lineLimit(1)
            .padding(.horizontal, RPSpace.m)
            .frame(height: 32)
            .background(selected ? Color.RP.Night.route : Color.RP.card, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.RP.Night.route : Color.RP.border, lineWidth: 1))
    }
}

/// A checkerboard: the universal sign for "transparent", behind the Clear Print preview.
struct TransparencyGrid: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 10
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.RP.Day.card))
            var y: CGFloat = 0, row = 0
            while y < size.height {
                var x: CGFloat = row % 2 == 0 ? 0 : cell
                while x < size.width {
                    context.fill(Path(CGRect(x: x, y: y, width: cell, height: cell)), with: .color(Color.RP.Day.border))
                    x += cell * 2
                }
                y += cell
                row += 1
            }
        }
        .accessibilityHidden(true)
    }
}

/// The Terrain preview while it loads (a blurred sample with progress) and while the driver is not Pro
/// (a dimmed sample). Never an empty black card.
struct TerrainPlaceholder: View {
    enum Kind: Equatable {
        case loading(Double?)
        case locked
        case offline
    }

    let kind: Kind

    var body: some View {
        ZStack {
            Color.RP.Night.background
            if let sample = ShareAssets.terrainSample {
                Image(uiImage: sample)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: kind == .locked ? 0 : 14)
                    .opacity(kind == .locked ? 0.55 : 0.7)
            }
            Color.RP.Night.background.opacity(kind == .locked ? 0.25 : 0.35)
            VStack(spacing: RPSpace.s) {
                switch kind {
                case .loading(let progress):
                    Text("Drawing the land…", comment: "Share sheet: the Terrain card is downloading elevation and rendering.")
                        .font(.rpText(size: 17, weight: .bold))
                    Text("Elevation for this trip’s area", comment: "Share sheet: under 'Drawing the land…'.")
                        .font(.rpText(size: 12))
                        .foregroundStyle(Color.RP.Night.textSecondary)
                    Group {
                        if let progress { ProgressView(value: progress) } else { ProgressView(value: 0.05) }
                    }
                    .tint(Color.RP.Night.route)
                    .frame(width: 150)
                case .locked:
                    ProBadge().scaleEffect(1.6).padding(.bottom, RPSpace.xs)
                    Text("Terrain is part of Pro", comment: "Share sheet: the Terrain preview for a driver without Pro.")
                        .font(.rpText(size: 17, weight: .bold))
                    Text("Your run across the land in 3D", comment: "Share sheet: under 'Terrain is part of Pro'.")
                        .font(.rpText(size: 12))
                        .foregroundStyle(Color.RP.Night.textSecondary)
                case .offline:
                    Image(systemName: "wifi.slash")
                        .font(.rpText(size: 26, weight: .semibold))
                        .foregroundStyle(Color.RP.Night.textSecondary)
                }
            }
            .foregroundStyle(Color.RP.Night.text)
            .multilineTextAlignment(.center)
            .padding(RPSpace.l)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("terrainPlaceholder")
    }
}
