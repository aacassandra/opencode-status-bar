import Cocoa
import UniformTypeIdentifiers
import AVFoundation
import DiskArbitration
import IOKit

// MARK: - Animation Style

enum AnimStyle: String, CaseIterable {
    case spark = "spark"
    case block = "block"
    case term = "term"
    case bounce = "bounce"
    case pulse = "pulse"
    case dots = "dots"
    case basic = "basic"
}

// MARK: - Config

struct SBConfig: Codable {
    var icon: IconConfig?
    var colors: ColorConfig?
    var labels: LabelConfig?
    var sound: SoundConfig?
    var display: DisplayConfig?
    var breakTime: BreakConfig?
    enum CodingKeys: String, CodingKey {
        case icon, colors, labels, sound, display
        case breakTime = "break"
    }

    struct IconConfig: Codable {
        var path: String?
        var size: Double?
    }
    struct ColorConfig: Codable {
        var thinking: [Double]?
        var idle: [Double]?
        var permission: [Double]?
        var tool: [Double]?
    }
    struct LabelConfig: Codable {
        var thinking: String?
        var waiting: String?
        var permission: String?
        var idle: String?
        var done: String?
        var breakTitle: String?
        var breakMessage: String?
    }
    struct SoundConfig: Codable {
        var path: String?
        var notifPath: String?
        var breakOnlyPath: String?
        var breakStartPath: String?
        var breakCompletePath: String?
        var minDuration: Double?
    }
    struct DisplayConfig: Codable {
        var showTimer: Bool?
        var hideIdleAfter: Double?
        var nameMax: Int?
        var boxWidth: Double?
    }
    struct BreakConfig: Codable {
        var enabled: Bool?
        var interval: Double?
        var duration: Double?
        var audioOnly: Bool?
        enum CodingKeys: String, CodingKey {
            case enabled, interval, duration, audioOnly
        }
    }
}

let colorPresets: [(String, [Double])] = [
    ("Blue",   [0.26, 0.52, 0.96, 1.0]),
    ("Green",  [0.22, 0.80, 0.46, 1.0]),
    ("Orange", [0.95, 0.61, 0.07, 1.0]),
    ("Purple", [0.56, 0.27, 0.91, 1.0]),
    ("Red",    [0.96, 0.26, 0.21, 1.0]),
    ("Teal",   [0.18, 0.75, 0.82, 1.0]),
    ("Yellow", [0.95, 0.89, 0.16, 1.0]),
    ("White",  [1.0,  1.0,  1.0,  1.0]),
]

// MARK: - ToggleView

final class ToggleView: NSView {
    static let w: CGFloat = 33, h: CGFloat = 16
    private let track = CALayer()
    private let knob = CALayer()
    private var lastToggle = Date.distantPast
    private var hovered = false
    var isOn: Bool { didSet { updateState(animated: true) } }
    var onToggle: ((Bool) -> Void)?

    init(isOn: Bool) {
        self.isOn = isOn
        super.init(frame: NSRect(x: 0, y: 0, width: ToggleView.w, height: ToggleView.h))
        layer = CALayer()
        wantsLayer = true
        track.frame = bounds
        track.cornerRadius = bounds.height / 2
        layer?.addSublayer(track)
        let kh = bounds.height - 4, kw = kh + 3
        knob.bounds = CGRect(x: 0, y: 0, width: kw, height: kh)
        knob.cornerRadius = kh / 2
        knob.backgroundColor = NSColor.white.cgColor
        layer?.addSublayer(knob)
        updateState(animated: false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: NSSize { NSSize(width: ToggleView.w, height: ToggleView.h) }

    private func knobCenter() -> CGPoint {
        let kw = knob.bounds.width
        return CGPoint(x: isOn ? bounds.width - kw / 2 - 2 : kw / 2 + 2, y: bounds.height / 2)
    }

    private func trackColor() -> CGColor {
        if isOn {
            let accent = NSColor.controlAccentColor
            return (hovered ? (accent.blended(withFraction: 0.10, of: .white) ?? accent) : accent).cgColor
        }
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let base: CGFloat = dark ? 1.0 : 0.0
        let alpha: CGFloat = (dark ? 0.30 : 0.34) + (hovered ? 0.10 : 0)
        return NSColor(white: base, alpha: alpha).cgColor
    }

    private func updateState(animated: Bool) {
        let toColor = trackColor()
        let toPos = knobCenter()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if animated {
            let spring = CASpringAnimation(keyPath: "position")
            spring.fromValue = NSValue(point: knob.presentation()?.position ?? knob.position)
            spring.toValue = NSValue(point: toPos)
            spring.damping = 16; spring.stiffness = 260; spring.mass = 1; spring.initialVelocity = 0
            spring.duration = spring.settlingDuration
            knob.add(spring, forKey: "position")
            let col = CABasicAnimation(keyPath: "backgroundColor")
            col.fromValue = track.presentation()?.backgroundColor ?? track.backgroundColor
            col.toValue = toColor
            col.duration = 0.2
            track.add(col, forKey: "backgroundColor")
        }
        knob.position = toPos
        track.backgroundColor = toColor
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateState(animated: false)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; updateState(animated: false) }
    override func mouseExited(with event: NSEvent) { hovered = false; updateState(animated: false) }

    override func mouseDown(with event: NSEvent) {
        guard Date().timeIntervalSince(lastToggle) > 0.1 else { return }
        lastToggle = Date()
        isOn.toggle()
        onToggle?(isOn)
    }
}

// MARK: - SessionRowView

final class SessionRowView: NSView {
    let id: String
    var onClick: (() -> Void)?
    private let iconView = NSImageView()
    private let nameField = NSTextField(labelWithString: "")
    private let timerField = NSTextField(labelWithString: "")
    private let pillView = NSImageView()
    private let pad: CGFloat = 14, iconSize: CGFloat = 16, rowH: CGFloat = 24, timerW: CGFloat = 74
    private let highlightView = NSVisualEffectView()
    private var hovered = false
    private var iconBaseTint: NSColor?
    private var pillNormal: NSImage?, pillSelected: NSImage?

    init(id: String, width: CGFloat) {
        self.id = id
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: rowH))
        autoresizingMask = [.width]
        highlightView.material = .selection
        highlightView.state = .active
        highlightView.isEmphasized = true
        highlightView.wantsLayer = true
        highlightView.layer?.cornerRadius = 5
        highlightView.isHidden = true
        addSubview(highlightView)
        iconView.frame = NSRect(x: pad, y: (rowH - iconSize) / 2, width: iconSize, height: iconSize)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.autoresizingMask = [.maxXMargin]
        addSubview(iconView)
        nameField.font = .menuFont(ofSize: 0)
        nameField.textColor = .labelColor
        nameField.lineBreakMode = .byTruncatingTail
        nameField.frame = NSRect(x: pad + iconSize + 8, y: (rowH - 16) / 2, width: 160, height: 16)
        nameField.autoresizingMask = [.maxXMargin]
        addSubview(nameField)
        timerField.font = NSFont.monospacedSystemFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize - 2, weight: .regular)
        timerField.textColor = .secondaryLabelColor
        timerField.alignment = .right
        timerField.autoresizingMask = [.minXMargin]
        addSubview(timerField)
        pillView.imageScaling = .scaleNone
        pillView.autoresizingMask = [.minXMargin]
        addSubview(pillView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setIcon(_ img: NSImage?) { iconView.image = img }

    func configure(icon: NSImage?, iconTint: NSColor?, name: String, timer: String?,
                   pillNormal: NSImage?, pillSelected: NSImage?, pillInset: CGFloat, timerGap: CGFloat) {
        let w = bounds.width
        iconView.image = icon
        iconBaseTint = iconTint
        iconView.contentTintColor = hovered ? .white : iconTint
        nameField.stringValue = name
        self.pillNormal = pillNormal; self.pillSelected = pillSelected
        let pill = hovered ? pillSelected : pillNormal
        var pillLeft = w - pillInset
        if let pill = pill {
            pillView.isHidden = false
            pillView.image = pill
            pillView.frame = NSRect(x: w - pillInset - pill.size.width, y: (rowH - pill.size.height) / 2,
                                    width: pill.size.width, height: pill.size.height)
            pillLeft = pillView.frame.minX
        } else { pillView.isHidden = true }
        if let timer = timer {
            timerField.isHidden = false
            timerField.stringValue = timer
            timerField.frame = NSRect(x: pillLeft - timerGap - timerW, y: (rowH - 16) / 2, width: timerW, height: 16)
        } else { timerField.isHidden = true }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { setHover(true) }
    override func mouseExited(with event: NSEvent) { setHover(false) }
    private func setHover(_ h: Bool) {
        hovered = h
        highlightView.isHidden = !h
        nameField.textColor = h ? .white : .labelColor
        timerField.textColor = h ? .white : .secondaryLabelColor
        iconView.contentTintColor = h ? .white : iconBaseTint
        if !pillView.isHidden { pillView.image = h ? pillSelected : pillNormal }
    }
    override func layout() {
        super.layout()
        highlightView.frame = bounds.insetBy(dx: 5, dy: 0)
    }
    override func mouseDown(with event: NSEvent) { onClick?() }
}

// MARK: - Helper Functions

func colorSwatchImage(_ rgba: [Double], size: CGFloat = 12) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        NSColor(srgbRed: CGFloat(rgba[0]), green: CGFloat(rgba[1]), blue: CGFloat(rgba[2]), alpha: CGFloat(rgba[3])).setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
        return true
    }
    return img
}

func rgbaEqual(_ a: [Double], _ b: [Double]) -> Bool {
    guard a.count == 4, b.count == 4 else { return false }
    return abs(a[0]-b[0])<0.01 && abs(a[1]-b[1])<0.01 && abs(a[2]-b[2])<0.01 && abs(a[3]-b[3])<0.01
}

func rgbaToString(_ rgba: [Double]) -> String {
    let r = Int(rgba[0]*255), g = Int(rgba[1]*255), b = Int(rgba[2]*255), a = Int(rgba[3]*100)
    return "\(r),\(g),\(b) (\(a)%)"
}

func diskType(forPath path: String) -> String {
    guard let session = DASessionCreate(nil),
          let url = URL(string: "file://\(path)"),
          let disk = DADiskCreateFromVolumePath(nil, session, url as CFURL) else {
        return "SSD"
    }

    // 1. Walk IORegistry from IOMedia parent chain looking for NVMe controller
    let media = DADiskCopyIOMedia(disk)
    if media != 0 {
        var current = media
        while current != 0 {
            if IOObjectConformsTo(current, "IONVMeController") != 0 {
                IOObjectRelease(media)
                return "NVME"
            }
            var parent: io_registry_entry_t = 0
            if IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) != KERN_SUCCESS {
                break
            }
            if current != media { IOObjectRelease(current) }
            current = parent
        }
        IOObjectRelease(media)
    }

    // 2. Fallback: check model name via DiskArbitration
    if let desc = DADiskCopyDescription(disk) {
        let nsdict = desc as NSDictionary
        if let model = nsdict[kDADiskDescriptionDeviceModelKey as NSString] as? String {
            let m = model.trimmingCharacters(in: .whitespaces).lowercased()
            if m.contains("hdd") || m.contains("wd ") || m.hasPrefix("st") || m.contains("seagate") { return "HDD" }
        }
    }

    return "SSD"
}

final class SystemStatRowView: NSView {
    private let label: String
    private let value: Double
    private let detail: String
    private let barColor: NSColor
    private let rowH: CGFloat = 22
    var onClick: (() -> Void)?
    private let highlightView = NSVisualEffectView()
    private var hovered = false

    init(label: String, value: Double, detail: String, barColor: NSColor, width: CGFloat) {
        self.label = label
        self.value = min(max(value, 0), 1)
        self.detail = detail
        self.barColor = barColor
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: rowH))
        autoresizingMask = [.width]
        toolTip = "\(label): \(detail) (\(Int(self.value * 100))%)"
        highlightView.material = .selection
        highlightView.state = .active
        highlightView.isEmphasized = true
        highlightView.wantsLayer = true
        highlightView.layer?.cornerRadius = 5
        highlightView.isHidden = true
        addSubview(highlightView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; highlightView.isHidden = false }
    override func mouseExited(with event: NSEvent) { hovered = false; highlightView.isHidden = true }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func layout() { super.layout(); highlightView.frame = bounds.insetBy(dx: 5, dy: 0) }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width
        if w <= 0 { return }
        let pad: CGFloat = 12, barH: CGFloat = 8, gap: CGFloat = 4
        let labelW: CGFloat = 38, detailW: CGFloat = 90
        let barX = pad + labelW + gap
        let barW = w - barX - detailW - pad
        let barY = (rowH - barH) / 2
        let isDark = effectiveAppearance.name == .darkAqua

        // bar background
        let bg = isDark ? NSColor(white: 0.25, alpha: 1) : NSColor(white: 0.85, alpha: 1)
        bg.setFill()
        let bgPath = NSBezierPath(roundedRect: NSRect(x: barX, y: barY, width: barW, height: barH), xRadius: 3, yRadius: 3)
        bgPath.fill()

        // bar fill
        if value > 0 {
            let fillW = max(4, barW * CGFloat(value))
            barColor.setFill()
            let fillPath = NSBezierPath(roundedRect: NSRect(x: barX, y: barY, width: fillW, height: barH), xRadius: 3, yRadius: 3)
            fillPath.fill()
        }

        // label text
        let labelColor = isDark ? NSColor(white: 0.8, alpha: 1) : NSColor(white: 0.35, alpha: 1)
        let labelStr = NSAttributedString(string: label, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: labelColor,
        ])
        labelStr.draw(at: NSPoint(x: pad, y: (rowH - labelStr.size().height) / 2))

        // detail text
        let detColor = isDark ? NSColor.white : NSColor.labelColor
        let detStr = NSAttributedString(string: detail, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: detColor,
        ])
        detStr.draw(at: NSPoint(x: w - detailW + 4, y: (rowH - detStr.size().height) / 2))
    }
}

// MARK: - StatusController

final class StatusController: NSObject, NSMenuDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let stateDir = (NSHomeDirectory() as NSString).appendingPathComponent(".config/opencode/statusbar/state.d")
    let opencodeDesktopBundleID = "com.anomaly.opencodedesktop"

    var pollTimer: Timer?
    var animTimer: Timer?
    var spinTimer: Timer?
    var spinAngle: CGFloat = 0
    var frameIdx = 0
    var pulseFrame = 0

    var stalePruneAge: TimeInterval { UserDefaults.standard.object(forKey: "hideIdleAfter") as? Double ?? 1800 }

    struct Session {
        var id: String, state: String, label: String, project: String, transcript: String
        var entrypoint: String
        var termProgram: String
        var pid: Int32
        var started: Bool
        var startedAt: Double, ts: Double
        var eff: String = ""

        init(json o: [String: Any], id: String) {
            self.id = id
            self.state = o["state"] as? String ?? "idle"
            self.label = o["label"] as? String ?? ""
            self.project = o["project"] as? String ?? ""
            self.transcript = o["transcript"] as? String ?? ""
            self.entrypoint = o["entrypoint"] as? String ?? ""
            self.termProgram = o["term_program"] as? String ?? ""
            self.pid = Int32(truncatingIfNeeded: (o["pid"] as? NSNumber)?.intValue ?? 0)
            self.started = o["started"] as? Bool ?? false
            self.startedAt = (o["startedAt"] as? NSNumber)?.doubleValue ?? 0
            self.ts = (o["ts"] as? NSNumber)?.doubleValue ?? 0
        }
    }
    var sessions: [String: Session] = [:]
    var fileMTimes: [String: Date] = [:]
    var soundPrev: [String: String] = [:]
    var turnStart: [String: Double] = [:]
    var sessionActiveStart: [String: Double] = [:]
    var menuIsOpen = false
    var sessionMenuItems: [(item: NSMenuItem, id: String)] = []
    var activeBase = ""
    var startedAt: Double = 0
    var activeColor: NSColor? = nil
    var cpuUsage: Double = 0
    var cpuCores: Int = 0
    var perCoreUsage: [Double] = []
    var ramUsed: UInt64 = 0
    var ramTotal: UInt64 = 0
    var diskFree: UInt64 = 0
    var diskTotal: UInt64 = 0
    var disks: [(name: String, free: UInt64, total: UInt64, isInternal: Bool, type: String)] = []
    var temperature: Double?
    var prevCpuTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?
    var systemStyle: String = "progress"
    var prevCoreTicks: [(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)]?
    var prevCoreTicksArray: [[UInt32]]?

    let amber = NSColor(srgbRed: 0.95, green: 0.73, blue: 0.18, alpha: 1)

    // MARK: Config

    var loadedConfig = SBConfig()
    var configMTime: Date?
    var currentColorKey: String?
    var cachedCustomIcon: NSImage?
    var cachedCustomIconPath: String?
    var aboutPanel: NSPanel?

    var configPath: String {
        (stateDir as NSString).deletingLastPathComponent + "/config.json"
    }

    func loadConfig() {
        let path = configPath
        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path),
              let config = try? JSONDecoder().decode(SBConfig.self, from: data) else {
            loadedConfig = SBConfig()
            return
        }
        loadedConfig = config
    }

    func saveConfig() {
        let path = configPath
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(loadedConfig) else { return }
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    func reloadConfigIfNeeded() {
        let path = configPath
        guard FileManager.default.fileExists(atPath: path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let m = attrs[.modificationDate] as? Date else { return }
        if configMTime != m {
            configMTime = m
            loadConfig()
            applyConfig()
        }
    }

    func applyConfig() {
        cachedCustomIcon = nil
        cachedCustomIconPath = nil
        evaluate()
    }

    func configColor(_ key: String) -> [Double]? {
        guard let c = loadedConfig.colors else { return nil }
        switch key {
        case "thinking":   return c.thinking
        case "idle":       return c.idle
        case "permission": return c.permission
        case "tool":       return c.tool
        default:           return nil
        }
    }

    func setConfigColor(_ key: String, _ rgba: [Double]) {
        if loadedConfig.colors == nil { loadedConfig.colors = SBConfig.ColorConfig() }
        switch key {
        case "thinking":   loadedConfig.colors?.thinking = rgba
        case "idle":       loadedConfig.colors?.idle = rgba
        case "permission": loadedConfig.colors?.permission = rgba
        case "tool":       loadedConfig.colors?.tool = rgba
        default:           break
        }
    }

    func resetConfigColor(_ key: String) {
        guard loadedConfig.colors != nil else { return }
        switch key {
        case "thinking":   loadedConfig.colors?.thinking = nil
        case "idle":       loadedConfig.colors?.idle = nil
        case "permission": loadedConfig.colors?.permission = nil
        case "tool":       loadedConfig.colors?.tool = nil
        default:           break
        }
    }

    func effectiveColor(for key: String) -> NSColor? {
        if let rgba = configColor(key) {
            return NSColor(srgbRed: CGFloat(rgba[0]), green: CGFloat(rgba[1]), blue: CGFloat(rgba[2]), alpha: CGFloat(rgba[3]))
        }
        switch key {
        case "permission": return amber
        default:           return nil
        }
    }

    func configLabel(_ key: String) -> String? {
        guard let l = loadedConfig.labels else { return nil }
        switch key {
        case "thinking":     return l.thinking
        case "waiting":      return l.waiting
        case "permission":   return l.permission
        case "idle":         return l.idle
        case "done":         return l.done
        case "breakTitle":   return l.breakTitle
        case "breakMessage": return l.breakMessage
        default:             return nil
        }
    }

    func setConfigLabel(_ key: String, _ value: String) {
        if loadedConfig.labels == nil { loadedConfig.labels = SBConfig.LabelConfig() }
        switch key {
        case "thinking":     loadedConfig.labels?.thinking = value
        case "waiting":      loadedConfig.labels?.waiting = value
        case "permission":   loadedConfig.labels?.permission = value
        case "idle":         loadedConfig.labels?.idle = value
        case "done":         loadedConfig.labels?.done = value
        case "breakTitle":   loadedConfig.labels?.breakTitle = value
        case "breakMessage": loadedConfig.labels?.breakMessage = value
        default:             break
        }
    }

    func defaultLabel(for key: String) -> String {
        switch key {
        case "thinking":     return "Thinking…"
        case "waiting":      return "Waiting permission"
        case "permission":   return "Waiting permission"
        case "idle":         return "Idle"
        case "done":         return "Done"
        case "breakTitle":   return "Break Time"
        case "breakMessage": return "Stand up, stretch, look away from screen"
        default:             return ""
        }
    }

    func customIconImage() -> NSImage? {
        guard let path = loadedConfig.icon?.path, !path.isEmpty,
              FileManager.default.fileExists(atPath: path) else { return nil }
        if path == cachedCustomIconPath, let cached = cachedCustomIcon { return cached }
        guard let img = NSImage(contentsOfFile: path) else { return nil }
        let targetSize = CGFloat(loadedConfig.icon?.size ?? 18)
        let resized = NSImage(size: NSSize(width: targetSize, height: targetSize), flipped: false) { rect in
            img.draw(in: rect)
            return true
        }
        resized.isTemplate = true
        cachedCustomIcon = resized
        cachedCustomIconPath = path
        return resized
    }

    var animStyle = AnimStyle.block
    var forcePulse = false
    var showTimer = false
    var playCompletionSound = false
    var playNotifSound = true
    var soundMinDuration: Double = {
        let v = UserDefaults.standard.double(forKey: "soundMinDuration")
        return v > 0 ? v : 60
    }()
    var audioPlayer: AVAudioPlayer?
    var notifPlayer: AVAudioPlayer?
    var countPlayer: AVAudioPlayer?
    var breakAudioPlayer: AVAudioPlayer?

    // MARK: Break Time
    let breakIcons = ["☕️", "🧘", "👀", "🌿", "🪴"]
    var breakEnabled: Bool = {
        let d = UserDefaults.standard
        return d.object(forKey: "breakEnabled") as? Bool ?? true
    }()
    var breakInterval: Double = {
        let v = UserDefaults.standard.double(forKey: "breakInterval")
        return v > 0 ? v : 1800
    }()
    var breakDuration: Double = {
        let v = UserDefaults.standard.double(forKey: "breakDuration")
        return v > 0 ? v : 10
    }()
    var breakAudioOnly = UserDefaults.standard.object(forKey: "breakAudioOnly") as? Bool ?? false
    var breakTimer: Timer?
    var breakCountdown = 0
    var breakActive = false
    var breakWindows: [NSWindow] = []
    var breakEventMonitors: [Any] = []
    var breakIconIndex = 0
    var breakCountdownTimer: Timer?

    func playCompletionChime() {
        guard playCompletionSound else { return }
        do {
            if let path = loadedConfig.sound?.path, !path.isEmpty,
               FileManager.default.fileExists(atPath: path) {
                audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            } else if let path = Bundle.main.path(forResource: "completion", ofType: "mp3") {
                audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            }
            audioPlayer?.volume = 1.0
            audioPlayer?.play()
        } catch {}
    }

    func playNotifChime() {
        guard playNotifSound else { return }
        do {
            if let path = loadedConfig.sound?.notifPath, !path.isEmpty,
               FileManager.default.fileExists(atPath: path) {
                notifPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            } else {
                let url = URL(fileURLWithPath: "/System/Library/Sounds/Tink.aiff")
                notifPlayer = try AVAudioPlayer(contentsOf: url)
            }
            notifPlayer?.volume = 1.0
            notifPlayer?.play()
        } catch {}
    }

    @objc func testSound() {
        do {
            if let path = loadedConfig.sound?.path, !path.isEmpty,
               FileManager.default.fileExists(atPath: path) {
                audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            } else if let path = Bundle.main.path(forResource: "completion", ofType: "mp3") {
                audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            }
            audioPlayer?.volume = 1.0
            audioPlayer?.play()
        } catch {}
    }

    // OpenCode geometric animation: blocks build/pulse
    let blockFrames: [NSImage] = {
        let side: CGFloat = 16
        let count = 8
        return (0..<count).map { i in
            let size = NSSize(width: side, height: side)
            let progress = CGFloat(i) / CGFloat(count - 1)
            let img = NSImage(size: size, flipped: false) { rect in
                guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
                let inset = CGFloat(8 - i) * 0.5
                let r = rect.insetBy(dx: inset, dy: inset)
                NSColor.black.withAlphaComponent(0.15 + progress * 0.85).setFill()
                ctx.fill(r)
                let inner = r.insetBy(dx: 2, dy: 2)
                NSColor.black.setFill()
                ctx.fill(inner)
                return true
            }
            img.isTemplate = true
            return img
        }
    }()

    let termGlyphs = ["▖", "▘", "▝", "▗"]
    let termSub = 12
    let termCycle: Double = 2.0
    lazy var termMasks: [NSImage] = termGlyphs.map { glyph in
        let side: CGFloat = 16
        let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold),
                .foregroundColor: NSColor.black,
            ]
            (glyph as NSString).draw(at: NSPoint(x: 2, y: 0), withAttributes: attrs)
            return true
        }
        img.isTemplate = true
        return img
    }

    let sparkFrameCount = 40

    var fps: Double {
        switch animStyle {
        case .spark:  return 15
        case .block:  return 12
        case .term:   return Double(termGlyphs.count * termSub) / termCycle
        case .bounce: return 20
        case .pulse:  return 15
        case .dots:  return 8
        case .basic: return 20
        }
    }
    var frameCount: Int {
        switch animStyle {
        case .spark:  return sparkFrameCount
        case .block:  return blockFrames.count
        case .term:   return termGlyphs.count * termSub
        case .bounce: return 16
        case .pulse:  return 20
        case .dots:   return 12
        case .basic:  return 60
        }
    }

    // MARK: Init

    override init() {
        super.init()
        loadConfig()
        let d = UserDefaults.standard
        if d.object(forKey: "showTimer") != nil { showTimer = d.bool(forKey: "showTimer") }
        if d.object(forKey: "completionSound") != nil { playCompletionSound = d.bool(forKey: "completionSound") }
        if d.object(forKey: "breakEnabled") != nil { breakEnabled = d.bool(forKey: "breakEnabled") }
        if d.object(forKey: "breakInterval") != nil { breakInterval = max(d.double(forKey: "breakInterval"), 1) }
        if d.object(forKey: "breakDuration") != nil { breakDuration = max(d.double(forKey: "breakDuration"), 1) }
        if d.object(forKey: "breakAudioOnly") != nil { breakAudioOnly = d.bool(forKey: "breakAudioOnly") }
        if let s = d.string(forKey: "animStyle"), let st = AnimStyle(rawValue: s) { animStyle = st }
        if let s = d.string(forKey: "systemStyle") { systemStyle = s }
        // config overrides UserDefaults
        if let v = loadedConfig.display?.showTimer { showTimer = v }
        if let v = loadedConfig.display?.hideIdleAfter { d.set(v, forKey: "hideIdleAfter") }
        if let v = loadedConfig.breakTime?.enabled { breakEnabled = v }
        if let v = loadedConfig.breakTime?.interval { breakInterval = v }
        if let v = loadedConfig.breakTime?.duration { breakDuration = v }
        if let v = loadedConfig.breakTime?.audioOnly { breakAudioOnly = v }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        render(label: "", color: nil, animate: false, startedAt: 0)
        updateSystemStats()
        let t = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
        tick()
        startBreakTimer()
        ensurePluginInstalled()
        checkForUpdate()
    }

    func ensurePluginInstalled() {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let pluginDir = "\(home)/.config/opencode/plugins"
        let pluginSrc = Bundle.main.path(forResource: "statusbar", ofType: "ts")
        let pluginDst = "\(pluginDir)/statusbar.ts"
        guard let src = pluginSrc else { return }
        try? fm.createDirectory(atPath: pluginDir, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: pluginDst) || fm.contentsEqual(atPath: src, andPath: pluginDst) == false {
            try? fm.removeItem(atPath: pluginDst)
            try? fm.copyItem(atPath: src, toPath: pluginDst)
        }
    }

    static func locateNode() -> String? {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        var candidates = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node",
            "\(home)/.volta/bin/node",
            "\(home)/.asdf/shims/node",
        ]
        let nvmDir = "\(home)/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvmDir) {
            for v in versions.sorted(by: >) { candidates.append("\(nvmDir)/\(v)/bin/node") }
        }
        for path in candidates where fm.isExecutableFile(atPath: path) { return path }
        for args in [["-ilc", "command -v node"], ["-lc", "command -v node"]] {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = args
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { continue }
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = (String(data: data, encoding: .utf8) ?? "")
                .split(separator: "\n").last.map(String.init)?
                .trimmingCharacters(in: .whitespaces) ?? ""
            if !path.isEmpty, fm.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    var currentVersion: String { (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0" }
    let releaseAPIURL = "https://api.github.com/repos/aacassandra/opencode-status-bar/releases/latest"
    let releasePageURL = "https://github.com/aacassandra/opencode-status-bar/releases/latest"

    func checkForUpdate() {
        let d = UserDefaults.standard
        let now = Date().timeIntervalSince1970
        if now - d.double(forKey: "lastUpdateCheck") < 3600 { return }
        guard let url = URL(string: releaseAPIURL) else { return }
        var req = URLRequest(url: url)
        req.setValue("OpenCodeStatusBar", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = obj["tag_name"] as? String else { return }
            let ver = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            DispatchQueue.main.async {
                UserDefaults.standard.set(ver, forKey: "latestVersion")
                UserDefaults.standard.set(now, forKey: "lastUpdateCheck")
            }
        }.resume()
    }

    func versionIsNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    @objc func openLatestRelease() {
        if let url = URL(string: releasePageURL) { NSWorkspace.shared.open(url) }
    }

    // MARK: Menu

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        spinTimer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.spinTick() }
        RunLoop.main.add(t, forMode: .common)
        spinTimer = t
    }
    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        sessionMenuItems.removeAll()
        spinTimer?.invalidate(); spinTimer = nil
    }

    func spinTick() {
        spinAngle += 5
        guard let img = rotatedSpinner(spinAngle) else { return }
        let now = Date().timeIntervalSince1970
        for (item, id) in sessionMenuItems {
            guard let s = sessions[id], let v = item.view as? SessionRowView else { continue }
            let eff = s.eff.isEmpty ? effectiveState(s, now: now) : s.eff
            if eff == "thinking" || eff == "tool" { v.setIcon(img) }
        }
    }

    func refreshOpenMenuRows() {
        let now = Date().timeIntervalSince1970
        for (item, id) in sessionMenuItems {
            guard let s = sessions[id], let v = item.view as? SessionRowView else { continue }
            let eff = s.eff.isEmpty ? effectiveState(s, now: now) : s.eff
            configureSessionRow(v, s, eff: eff)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        populateMenu(menu)
    }

    func populateMenu(_ menu: NSMenu) {
        let cfg = uiConfig()
        menu.removeAllItems()
        checkForUpdate()

        // --- About
        let aboutItem = NSMenuItem(title: "About OpenCode Status Bar", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(.separator())

        // --- Sessions
        sessionMenuItems.removeAll()
        let now = Date().timeIntervalSince1970
        let allOrdered = sessions.values.sorted { $0.ts > $1.ts }
        let ordered = allOrdered.filter { s in
                let eff = s.eff.isEmpty ? effectiveState(s, now: now) : s.eff
                let resting = !(eff == "permission" || eff == "thinking" || eff == "tool")
                let gated = s.entrypoint == "opencode-desktop"
                return !gated || s.started || !resting
            }
        var visible = ordered.filter { s in
            let eff = s.eff.isEmpty ? effectiveState(s, now: now) : s.eff
            let resting = !(eff == "permission" || eff == "thinking" || eff == "tool")
            return !(stalePruneAge > 0 && resting && now - s.ts > stalePruneAge)
        }
        if visible.isEmpty, let lead = ordered.first { visible = [lead] }

        if !visible.isEmpty {
            menu.addItem(header("Sessions"))
            for s in visible {
                let eff = s.eff.isEmpty ? effectiveState(s, now: now) : s.eff
                let view = SessionRowView(id: s.id, width: CGFloat(cfg["boxWidth"] ?? 300))
                let sid = s.id, ep = s.entrypoint, tp = s.termProgram
                view.onClick = { [weak self] in menu.cancelTracking(); self?.openSession(sid, entrypoint: ep, termProgram: tp) }
                configureSessionRow(view, s, eff: eff)
                let it = NSMenuItem()
                it.view = view
                menu.addItem(it)
                sessionMenuItems.append((it, s.id))
            }
            menu.addItem(.separator())
        } else if opencodeDesktopRunning() {
            menu.addItem(header("Sessions"))
            let open = NSMenuItem(title: "Open OpenCode", action: #selector(openOpencode), keyEquivalent: "")
            open.target = self
            menu.addItem(open)
            menu.addItem(.separator())
        }

        // --- System Info
        menu.addItem(header("System"))

        if systemStyle == "progress" {
            let sysW: CGFloat = cfg["boxWidth"] ?? 300
            let openActivityMtr = { menu.cancelTracking()
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")) }

            let cpuPct = cpuUsage / 100.0
            let cpuLabel = cpuCores > 0 ? "CPU(\(cpuCores))" : "CPU"
            let cpuDetail = String(format: "%.0f%%", cpuUsage)
            let cpuColor: NSColor = cpuUsage > 80 ? .systemRed : cpuUsage > 50 ? .systemOrange : .systemBlue
            let cpuRow = SystemStatRowView(label: cpuLabel, value: cpuPct, detail: cpuDetail, barColor: cpuColor, width: sysW)
            cpuRow.onClick = openActivityMtr
            if !perCoreUsage.isEmpty {
                let coreStr = perCoreUsage.enumerated().map { i, v in "C\(i+1): \(Int(v))%" }.joined(separator: "  ")
                cpuRow.toolTip = coreStr
            }
            let cpuItem = NSMenuItem(); cpuItem.view = cpuRow; menu.addItem(cpuItem)

            let ramPct = ramTotal > 0 ? Double(ramUsed) / Double(ramTotal) : 0
            let usedGB = Double(ramUsed) / 1_073_741_824
            let totalGB = Double(ramTotal) / 1_073_741_824
            let ramDetail = String(format: "%.1f/%.0f", usedGB, totalGB)
            let ramColor: NSColor = ramPct > 0.9 ? .systemRed : ramPct > 0.75 ? .systemOrange : .systemGreen
            let ramRow = SystemStatRowView(label: "RAM", value: ramPct, detail: ramDetail, barColor: ramColor, width: sysW)
            ramRow.onClick = openActivityMtr
            let ramItem = NSMenuItem(); ramItem.view = ramRow; menu.addItem(ramItem)

            var extCount = 0
            for dsk in disks {
                let dskPct = dsk.total > 0 ? Double(dsk.total - dsk.free) / Double(dsk.total) : 0
                let usedDSK = Double(dsk.total - dsk.free) / 1_073_741_824
                let totalDSK = Double(dsk.total) / 1_073_741_824
                let dskDetail = String(format: "%.0f/%.0f", usedDSK, totalDSK)
                let dskColor: NSColor = dskPct > 0.9 ? .systemRed : dskPct > 0.8 ? .systemOrange : .systemOrange
                let label: String
                if dsk.isInternal {
                    label = "DSK"
                } else {
                    extCount += 1
                    let shortName = dsk.name.count > 4 ? String(dsk.name.prefix(4)) : dsk.name
                    label = shortName.uppercased()
                }
                let dskRow = SystemStatRowView(label: label, value: dskPct, detail: dskDetail, barColor: dskColor, width: sysW)
                dskRow.onClick = openActivityMtr
                dskRow.toolTip = "\(dsk.type): \(label) (\(dskDetail))"
                let dskItem = NSMenuItem(); dskItem.view = dskRow; menu.addItem(dskItem)
            }

            if let temp = temperature, temp > 5 {
                let tempPct = min(temp / 100, 1)
                let tempDetail = String(format: "%.0f°C", temp)
                let tempColor: NSColor = temp > 80 ? .systemRed : temp > 60 ? .systemOrange : .systemGray
                let tempRow = SystemStatRowView(label: "TMP", value: tempPct, detail: tempDetail, barColor: tempColor, width: sysW)
                let tempItem = NSMenuItem(); tempItem.view = tempRow; menu.addItem(tempItem)
            }
        } else {
            let menuW = CGFloat(cfg["boxWidth"] ?? 300)
            // Row 1: CPU + RAM
            let cpuStr = String(format: "%.0f%%", cpuUsage)
            let usedGB  = Double(ramUsed)  / 1_073_741_824
            let totalGB = Double(ramTotal) / 1_073_741_824
            let ramStr  = String(format: "%.1f/%.0fGB", usedGB, totalGB)
            let row1 = basicTwoColView(
                left:  ("CPU", cpuStr),
                right: ("RAM", ramStr),
                width: menuW
            )
            let row1Item = NSMenuItem(); row1Item.view = row1; menu.addItem(row1Item)

            // Disk rows: pair disks 2-per-row
            var extIdx = 0
            var diskCells: [(header: String, detail: String)] = []
            for dsk in disks {
                let totalDSK = Double(dsk.total) / 1_073_741_824
                let pct      = dsk.total > 0 ? Int(Double(dsk.total - dsk.free) / Double(dsk.total) * 100) : 0
                let detail   = "\(dsk.type): \(String(format: "%.0fGB/%d%%", totalDSK, pct))"
                let header: String
                if dsk.isInternal {
                    header = "DSK"
                } else {
                    extIdx += 1
                    let shortName = String(dsk.name.prefix(10))
                    header = "EXT\(extIdx) (\(shortName))"
                }
                diskCells.append((header, detail))
            }
            // pair into rows of 2
            var i = 0
            while i < diskCells.count {
                let left = diskCells[i]
                let right = i + 1 < diskCells.count ? diskCells[i + 1] : nil
                let rowView = basicTwoColView(left: left, right: right, width: menuW)
                let rowItem = NSMenuItem(); rowItem.view = rowView; menu.addItem(rowItem)
                i += 2
            }

            if let t = temperature {
                let tempItem = NSMenuItem(title: String(format: "Temp: %.0f°C", t), action: nil, keyEquivalent: "")
                tempItem.isEnabled = false
                menu.addItem(tempItem)
            }
        }

        menu.addItem(.separator())

        // --- Options
        menu.addItem(header("Options"))
        menu.addItem(toggleRow(title: "Show timer", isOn: showTimer) { [weak self] on in
            self?.showTimer = on
            UserDefaults.standard.set(on, forKey: "showTimer")
            if self?.loadedConfig.display == nil { self?.loadedConfig.display = SBConfig.DisplayConfig() }
            self?.loadedConfig.display?.showTimer = on
            self?.saveConfig()
            self?.applyTitle()
        })
        let durLabel = soundMinDuration >= 60 ? "\(Int(soundMinDuration / 60))m" : "\(Int(soundMinDuration))s"
        menu.addItem(toggleRow(title: "Completion sound (≥\(durLabel))", isOn: playCompletionSound) { [weak self] on in
            guard let self = self else { return }
            self.playCompletionSound = on
            UserDefaults.standard.set(on, forKey: "completionSound")
            if let menu = self.statusItem.menu {
                self.populateMenu(menu)
            }
        })
        if playCompletionSound {
            let durItem = NSMenuItem(title: "Min duration: \(durLabel)", action: nil, keyEquivalent: "")
            let durSub = NSMenu()
            let choices: [(title: String, value: Double)] = [
                ("0s (always)", 0), ("10s", 10), ("30s", 30),
                ("1m", 60), ("2m", 120), ("5m", 300),
            ]
            for (title, val) in choices {
                let it = NSMenuItem(title: title, action: #selector(chooseMinDuration(_:)), keyEquivalent: "")
                it.target = self
                it.representedObject = val
                it.state = soundMinDuration == val ? NSControl.StateValue.on : NSControl.StateValue.off
                durSub.addItem(it)
            }
            durItem.submenu = durSub
            durItem.indentationLevel = 1
            menu.addItem(durItem)

            let testSoundItem = NSMenuItem(title: "Test Sound", action: #selector(testSound), keyEquivalent: "")
            testSoundItem.target = self
            testSoundItem.indentationLevel = 1
            menu.addItem(testSoundItem)
        }

        // Break Time submenu
        let bi = Int(breakInterval); let bIntervalLabel = bi >= 3600 ? "\(bi / 3600)h \((bi % 3600) / 60)m" : bi >= 60 ? "\(bi / 60)m" : "\(bi)s"
        let bDurLabel = "\(Int(breakDuration))s"
        let breakParent = NSMenuItem(title: "Break Time", action: nil, keyEquivalent: "")
        let breakSub = NSMenu()
        breakSub.addItem(toggleRow(title: "Enabled", isOn: breakEnabled) { [weak self] on in
            guard let self = self else { return }
            self.breakEnabled = on
            UserDefaults.standard.set(on, forKey: "breakEnabled")
            if self.loadedConfig.breakTime == nil { self.loadedConfig.breakTime = SBConfig.BreakConfig() }
            self.loadedConfig.breakTime?.enabled = on
            self.saveConfig()
            if on { self.startBreakTimer() } else { self.cancelBreakTimer() }
        })
        breakSub.addItem(toggleRow(title: "Sound Only", isOn: breakAudioOnly) { [weak self] on in
            guard let self = self else { return }
            self.breakAudioOnly = on
            UserDefaults.standard.set(on, forKey: "breakAudioOnly")
            if self.loadedConfig.breakTime == nil { self.loadedConfig.breakTime = SBConfig.BreakConfig() }
            self.loadedConfig.breakTime?.audioOnly = on
            self.saveConfig()
            if self.breakEnabled { self.startBreakTimer() }

            if on {
                while breakSub.numberOfItems > 3 {
                    breakSub.removeItem(at: breakSub.numberOfItems - 1)
                }
            } else {
                let bDurLabel = "\(Int(self.breakDuration))s"
                let breakDurItem = NSMenuItem(title: "Duration: \(bDurLabel)", action: nil, keyEquivalent: "")
                let breakDurSub = NSMenu()
                for (name, val) in [("5s", 5.0), ("10s", 10.0), ("15s", 15.0), ("30s", 30.0)] {
                    let it = NSMenuItem(title: name, action: #selector(self.chooseBreakDuration(_:)), keyEquivalent: "")
                    it.target = self
                    it.representedObject = val
                    it.state = self.breakDuration == val ? NSControl.StateValue.on : NSControl.StateValue.off
                    breakDurSub.addItem(it)
                }
                breakDurItem.submenu = breakDurSub
                breakSub.addItem(breakDurItem)

            }
        })
        let breakIntItem = NSMenuItem(title: "Interval: \(bIntervalLabel)", action: nil, keyEquivalent: "")
        let breakIntSub = NSMenu()
        for (name, val) in [("15m", 900.0), ("30m", 1800.0), ("45m", 2700.0), ("60m", 3600.0)] {
            let it = NSMenuItem(title: name, action: #selector(chooseBreakInterval(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = val
            it.state = breakInterval == val ? NSControl.StateValue.on : NSControl.StateValue.off
            breakIntSub.addItem(it)
        }
        let customInt = NSMenuItem(title: "Custom…", action: #selector(chooseCustomInterval), keyEquivalent: "")
        customInt.target = self
        breakIntSub.addItem(NSMenuItem.separator())
        breakIntSub.addItem(customInt)
        breakIntItem.submenu = breakIntSub
        breakSub.addItem(breakIntItem)

        if !breakAudioOnly {
            let breakDurItem = NSMenuItem(title: "Duration: \(bDurLabel)", action: nil, keyEquivalent: "")
            let breakDurSub = NSMenu()
            for (name, val) in [("5s", 5.0), ("10s", 10.0), ("15s", 15.0), ("30s", 30.0)] {
                let it = NSMenuItem(title: name, action: #selector(chooseBreakDuration(_:)), keyEquivalent: "")
                it.target = self
                it.representedObject = val
                it.state = breakDuration == val ? NSControl.StateValue.on : NSControl.StateValue.off
                breakDurSub.addItem(it)
            }
            breakDurItem.submenu = breakDurSub
            breakSub.addItem(breakDurItem)

        }

        breakParent.submenu = breakSub
        menu.addItem(breakParent)

        let animParent = NSMenuItem(title: "Animation Style", action: nil, keyEquivalent: "")
        let animSub = NSMenu()
        for (style, name) in [(AnimStyle.spark, "OpenCode Spark"), (AnimStyle.block, "Block Build"),
                               (AnimStyle.term, "Terminal Pulse"), (AnimStyle.bounce, "Bounce"),
                               (AnimStyle.pulse, "Pulse"), (AnimStyle.dots, "Dots"),
                               (AnimStyle.basic, "OpenCode Basic")] {
            let it = NSMenuItem(title: name, action: #selector(chooseStyle(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = style.rawValue
            it.state = animStyle == style ? .on : .off
            animSub.addItem(it)
        }
        animParent.submenu = animSub
        menu.addItem(animParent)

        let hideParent = NSMenuItem(title: "Hide idle sessions", action: nil, keyEquivalent: "")
        let hideSub = NSMenu()
        let curHide = stalePruneAge
        for (name, secs) in [("5 minutes", 300.0), ("15 minutes", 900.0), ("30 minutes", 1800.0), ("1 hour", 3600.0), ("Never", 0.0)] {
            let it = NSMenuItem(title: name, action: #selector(chooseHideIdle(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = secs
            it.state = curHide == secs ? .on : .off
            hideSub.addItem(it)
        }
        hideParent.submenu = hideSub
        menu.addItem(hideParent)

        // Launch at Login
        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = launchAtLoginEnabled() ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(.separator())

        // Customize submenu
        let customizeParent = NSMenuItem(title: "Customize", action: nil, keyEquivalent: "")
        let customizeSub = NSMenu()

        let iconItem = NSMenuItem(title: "Change Icon…", action: #selector(pickIcon), keyEquivalent: "")
        iconItem.target = self
        customizeSub.addItem(iconItem)

        let soundParent = NSMenuItem(title: "Change Sound", action: nil, keyEquivalent: "")
        let soundSub = NSMenu()
        let compItem = NSMenuItem(title: "Completion…", action: #selector(pickSound), keyEquivalent: "")
        compItem.target = self
        soundSub.addItem(compItem)
        let notifItem = NSMenuItem(title: "Permission…", action: #selector(pickNotifSound), keyEquivalent: "")
        notifItem.target = self
        soundSub.addItem(notifItem)
        soundSub.addItem(NSMenuItem.separator())
        let btLabel = NSMenuItem(title: "Break Time", action: nil, keyEquivalent: "")
        btLabel.isEnabled = false
        soundSub.addItem(btLabel)
        let breakOnlyItem = NSMenuItem(title: "Sound Only…", action: #selector(pickBreakOnlySound), keyEquivalent: "")
        breakOnlyItem.target = self
        soundSub.addItem(breakOnlyItem)
        let breakStartItem = NSMenuItem(title: "Starting…", action: #selector(pickBreakStartSound), keyEquivalent: "")
        breakStartItem.target = self
        soundSub.addItem(breakStartItem)
        let breakCompleteItem = NSMenuItem(title: "Completion…", action: #selector(pickBreakCompleteSound), keyEquivalent: "")
        breakCompleteItem.target = self
        soundSub.addItem(breakCompleteItem)
        soundParent.submenu = soundSub
        customizeSub.addItem(soundParent)

        // System Style submenu
        let sysStyleParent = NSMenuItem(title: "System Style", action: nil, keyEquivalent: "")
        let sysStyleSub = NSMenu()
        for (raw, name) in [("basic", "Basic"), ("progress", "ProgressBar")] {
            let it = NSMenuItem(title: name, action: #selector(chooseSystemStyle(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = raw
            it.state = systemStyle == raw ? .on : .off
            sysStyleSub.addItem(it)
        }
        sysStyleParent.submenu = sysStyleSub
        customizeSub.addItem(sysStyleParent)

        // Colors submenu
        let colorsParent = NSMenuItem(title: "Colors", action: nil, keyEquivalent: "")
        let colorsSub = NSMenu()
        for key in ["thinking", "idle", "permission", "tool"] {
            let cap = key.capitalized
            let sub = NSMenuItem(title: cap, action: nil, keyEquivalent: "")
            let subMenu = NSMenu()
            let current = configColor(key)
            for (name, rgba) in colorPresets {
                let it = NSMenuItem(title: name, action: #selector(setColor(_:)), keyEquivalent: "")
                it.target = self
                it.representedObject = (key as NSString).appending("|\(rgba[0]),\(rgba[1]),\(rgba[2]),\(rgba[3])")
                it.image = colorSwatchImage(rgba)
                if let c = current, rgbaEqual(c, rgba) { it.state = .on }
                subMenu.addItem(it)
            }
            subMenu.addItem(.separator())
            let custom = NSMenuItem(title: "Custom…", action: #selector(openColorPanel(_:)), keyEquivalent: "")
            custom.target = self
            custom.representedObject = key
            if let c = current {
                let allPresets = colorPresets.contains { rgbaEqual($0.1, c) }
                if !allPresets { custom.state = .on }
            }
            subMenu.addItem(custom)
            let reset = NSMenuItem(title: "Reset", action: #selector(resetColor(_:)), keyEquivalent: "")
            reset.target = self
            reset.representedObject = key
            subMenu.addItem(reset)
            sub.submenu = subMenu
            colorsSub.addItem(sub)
        }
        colorsParent.submenu = colorsSub
        customizeSub.addItem(colorsParent)

        // Labels submenu
        let labelsParent = NSMenuItem(title: "Labels", action: nil, keyEquivalent: "")
        let labelsSub = NSMenu()
        let labelEntries: [(String, String)] = [
            ("thinking", "Thinking"), ("waiting", "Waiting"),
            ("idle", "Idle"), ("done", "Done"),
            ("breakTitle", "Break Title"), ("breakMessage", "Break Message"),
        ]
        for (key, display) in labelEntries {
            let label = configLabel(key) ?? defaultLabel(for: key)
            let it = NSMenuItem(title: "\(display): \"\(label)\"", action: #selector(editLabel(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = key
            labelsSub.addItem(it)
        }
        labelsParent.submenu = labelsSub
        customizeSub.addItem(labelsParent)

        let resetAll = NSMenuItem(title: "Reset All Customizations", action: #selector(resetAllConfig), keyEquivalent: "")
        resetAll.target = self
        customizeSub.addItem(resetAll)

        customizeParent.submenu = customizeSub
        menu.addItem(customizeParent)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Version \(currentVersion)", action: nil, keyEquivalent: ""))
        if let latest = UserDefaults.standard.string(forKey: "latestVersion"), versionIsNewer(latest, than: currentVersion) {
            let up = NSMenuItem(title: "Update available", action: #selector(openLatestRelease), keyEquivalent: "")
            up.target = self
            menu.addItem(up)
        }
        let q = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        q.target = self
        menu.addItem(q)
    }

    func header(_ title: String) -> NSMenuItem {
        if #available(macOS 14.0, *) { return NSMenuItem.sectionHeader(title: title) }
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.isEnabled = false
        return it
    }

    // Basic style: 2-column info row. right is optional (nil = left spans full width).
    func basicTwoColView(
        left:  (header: String, detail: String),
        right: (header: String, detail: String)?,
        width: CGFloat
    ) -> NSView {
        let rowH: CGFloat = 36, pad: CGFloat = 14
        let view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: rowH))
        view.autoresizingMask = [.width]

        let colW = right != nil ? (width - pad * 2) / 2 : (width - pad * 2)
        let isDark = NSApp.effectiveAppearance.name == .darkAqua

        func addCell(x: CGFloat, hdr: String, det: String) {
            let headerLabel = NSTextField(labelWithString: hdr)
            headerLabel.font = .monospacedSystemFont(ofSize: 10, weight: .semibold)
            headerLabel.textColor = isDark ? NSColor(white: 0.6, alpha: 1) : NSColor(white: 0.45, alpha: 1)
            headerLabel.frame = NSRect(x: x, y: rowH / 2 + 1, width: colW, height: 14)
            headerLabel.autoresizingMask = [.width]
            view.addSubview(headerLabel)

            let detailLabel = NSTextField(labelWithString: det)
            detailLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            detailLabel.textColor = .labelColor
            detailLabel.frame = NSRect(x: x, y: 4, width: colW, height: 14)
            detailLabel.autoresizingMask = [.width]
            view.addSubview(detailLabel)
        }

        addCell(x: pad,          hdr: left.header,  det: left.detail)
        if let r = right {
            addCell(x: pad + colW, hdr: r.header, det: r.detail)
        }
        return view
    }

    func toggleRow(title: String, isOn: Bool, onToggle: @escaping (Bool) -> Void) -> NSMenuItem {
        let width = CGFloat(uiConfig()["boxWidth"] ?? 300), height: CGFloat = 24, leftInset: CGFloat = 14, rightInset: CGFloat = 12
        let row = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        row.autoresizingMask = [.width]

        let labelFont = NSFont.menuFont(ofSize: 0)
        let attr = NSMutableAttributedString(string: title, attributes: [.font: labelFont, .foregroundColor: NSColor.labelColor])
        if let r = title.range(of: " (") {
            attr.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: NSRange(r.lowerBound..<title.endIndex, in: title))
        }
        let label = NSTextField(labelWithAttributedString: attr)
        label.sizeToFit()
        label.setFrameOrigin(NSPoint(x: leftInset, y: (height - label.frame.height) / 2))
        label.autoresizingMask = [.maxXMargin]
        row.addSubview(label)

        let toggle = ToggleView(isOn: isOn)
        toggle.onToggle = onToggle
        toggle.setFrameOrigin(NSPoint(x: width - toggle.frame.width - rightInset, y: (height - toggle.frame.height) / 2))
        toggle.autoresizingMask = [.minXMargin]
        row.addSubview(toggle)

        let item = NSMenuItem()
        item.view = row
        item.isEnabled = false
        return item
    }

    // MARK: Color Picker Actions

    @objc func setColor(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let sep = raw.firstIndex(of: "|") else { return }
        let key = String(raw[..<sep])
        let rgbaStr = String(raw[raw.index(after: sep)...])
        let parts = rgbaStr.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4 else { return }
        setConfigColor(key, parts)
        saveConfig()
        applyConfig()
    }

    @objc func openColorPanel(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        currentColorKey = key
        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        panel.isContinuous = true
        if let rgba = configColor(key) {
            panel.color = NSColor(srgbRed: CGFloat(rgba[0]), green: CGFloat(rgba[1]), blue: CGFloat(rgba[2]), alpha: CGFloat(rgba[3]))
        } else {
            panel.color = key == "permission" ? amber : NSColor.controlAccentColor
        }
        panel.orderFront(nil)
        NotificationCenter.default.addObserver(self, selector: #selector(colorPanelClosed), name: NSWindow.willCloseNotification, object: panel)
    }

    @objc func colorPanelChanged(_ sender: NSColorPanel) {
        guard let key = currentColorKey else { return }
        let color = sender.color.usingColorSpace(.sRGB) ?? sender.color
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let rgba = [Double(r), Double(g), Double(b), Double(a)]
        setConfigColor(key, rgba)
        saveConfig()
        applyConfig()
    }

    @objc func colorPanelClosed() {
        currentColorKey = nil
    }

    @objc func resetColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        resetConfigColor(key)
        saveConfig()
        applyConfig()
    }

    // MARK: Icon / Sound Pickers

    @objc func pickIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, UTType(filenameExtension: "icns")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Choose Status Bar Icon"
        panel.message = "Select a PNG or ICNS image (will be resized to 18×18)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if loadedConfig.icon == nil { loadedConfig.icon = SBConfig.IconConfig() }
        loadedConfig.icon?.path = url.path
        saveConfig()
        applyConfig()
    }

    @objc func pickSound() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mp3, .wav, UTType(filenameExtension: "caf"), UTType(filenameExtension: "aiff"), UTType(filenameExtension: "m4a")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Choose Completion Sound"
        panel.message = "Select an audio file for the completion chime"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if loadedConfig.sound == nil { loadedConfig.sound = SBConfig.SoundConfig() }
        loadedConfig.sound?.path = url.path
        saveConfig()
        applyConfig()
    }

    @objc func pickNotifSound() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mp3, .wav, UTType(filenameExtension: "caf"), UTType(filenameExtension: "aiff"), UTType(filenameExtension: "m4a")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Choose Permission Sound"
        panel.message = "Select an audio file for the permission notification"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if loadedConfig.sound == nil { loadedConfig.sound = SBConfig.SoundConfig() }
        loadedConfig.sound?.notifPath = url.path
        saveConfig()
        applyConfig()
    }

    @objc func pickBreakOnlySound() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mp3, .wav, UTType(filenameExtension: "caf"), UTType(filenameExtension: "aiff"), UTType(filenameExtension: "m4a")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Choose Break Sound Only"
        panel.message = "Select an audio file for the break countdown tick"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if loadedConfig.sound == nil { loadedConfig.sound = SBConfig.SoundConfig() }
        loadedConfig.sound?.breakOnlyPath = url.path
        saveConfig()
        applyConfig()
    }

    @objc func pickBreakStartSound() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mp3, .wav, UTType(filenameExtension: "caf"), UTType(filenameExtension: "aiff"), UTType(filenameExtension: "m4a")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Choose Break Starting Sound"
        panel.message = "Select an audio file for when the break overlay appears"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if loadedConfig.sound == nil { loadedConfig.sound = SBConfig.SoundConfig() }
        loadedConfig.sound?.breakStartPath = url.path
        saveConfig()
        applyConfig()
    }

    @objc func pickBreakCompleteSound() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mp3, .wav, UTType(filenameExtension: "caf"), UTType(filenameExtension: "aiff"), UTType(filenameExtension: "m4a")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Choose Break Completion Sound"
        panel.message = "Select an audio file for when the break finishes"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if loadedConfig.sound == nil { loadedConfig.sound = SBConfig.SoundConfig() }
        loadedConfig.sound?.breakCompletePath = url.path
        saveConfig()
        applyConfig()
    }

    // MARK: Label Editing

    @objc func editLabel(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        let current = configLabel(key) ?? defaultLabel(for: key)
        let alert = NSAlert()
        alert.messageText = "Edit \"\(key.capitalized)\" Label"
        alert.informativeText = "Enter a custom label for the \(key) state:"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = current
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        setConfigLabel(key, value)
        saveConfig()
        applyConfig()
    }

    // MARK: Launch at Login

    func launchAtLoginPlist() -> String {
        NSHomeDirectory() + "/Library/LaunchAgents/com.local.opencodestatusbar.plist"
    }

    func launchAtLoginEnabled() -> Bool {
        FileManager.default.fileExists(atPath: launchAtLoginPlist())
    }

    func setLaunchAtLogin(_ enable: Bool) {
        let path = launchAtLoginPlist()
        if enable {
            let bundlePath = Bundle.main.bundlePath
            let plist: [String: Any] = [
                "Label": "com.local.opencodestatusbar",
                "ProgramArguments": ["/usr/bin/open", bundlePath as NSString],
                "RunAtLoad": true,
                "KeepAlive": false,
            ]
            guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return }
            try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        } else {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    @objc func toggleLaunchAtLogin() {
        let enabled = launchAtLoginEnabled()
        setLaunchAtLogin(!enabled)
    }

    @objc func resetAllConfig() {
        // delete uploaded sound files
        if let s = loadedConfig.sound {
            for p in [s.path, s.notifPath, s.breakOnlyPath, s.breakStartPath, s.breakCompletePath] {
                if let p, !p.isEmpty, FileManager.default.fileExists(atPath: p) {
                    try? FileManager.default.removeItem(atPath: p)
                }
            }
        }
        let path = configPath
        try? FileManager.default.removeItem(atPath: path)
        configMTime = nil
        loadConfig()
        applyConfig()
    }

    // MARK: About Window

    @objc func showAbout() {
        if aboutPanel?.isVisible == true { aboutPanel?.orderFront(nil); return }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 300),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        aboutPanel = panel
        panel.center()
        panel.title = ""
        panel.isFloatingPanel = true
        panel.titlebarAppearsTransparent = true

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 300))

        let iconView = NSImageView(frame: NSRect(x: 140, y: 220, width: 40, height: 40))
        iconView.image = NSApp.applicationIconImage ?? statusItem.button?.image
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 8
        iconView.layer?.masksToBounds = true
        content.addSubview(iconView)

        let nameField = NSTextField(labelWithString: "OpenCode Status Bar")
        nameField.font = .boldSystemFont(ofSize: 15)
        nameField.alignment = .center
        nameField.frame = NSRect(x: 0, y: 190, width: 320, height: 20)
        content.addSubview(nameField)

        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.0"
        let verField = NSTextField(labelWithString: "Version \(ver)")
        verField.font = .systemFont(ofSize: 12)
        verField.textColor = .secondaryLabelColor
        verField.alignment = .center
        verField.frame = NSRect(x: 0, y: 170, width: 320, height: 18)
        content.addSubview(verField)

        let sep1 = NSBox(frame: NSRect(x: 40, y: 150, width: 240, height: 1))
        sep1.boxType = .separator
        content.addSubview(sep1)

        let contribLabel = NSTextField(labelWithString: "Contributors")
        contribLabel.font = .boldSystemFont(ofSize: 12)
        contribLabel.alignment = .center
        contribLabel.frame = NSRect(x: 0, y: 130, width: 320, height: 18)
        content.addSubview(contribLabel)

        let linkFont = NSFont.systemFont(ofSize: 12)
        let contributorData = [("ardith666", "https://github.com/ardith666"), ("afif cassandra", "https://github.com/aacassandra")]
        for (i, (name, urlStr)) in contributorData.enumerated() {
            let btn = URLButton(title: name, target: self, action: #selector(openContributorURL(_:)))
            btn.setButtonType(NSButton.ButtonType.momentaryPushIn)
            btn.isBordered = false
            btn.font = linkFont
            btn.frame = NSRect(x: 60, y: Double(86 - i * 22), width: 200, height: 20)
            btn.contentTintColor = NSColor.linkColor
            btn.refusesFirstResponder = true
            let attrTitle = NSAttributedString(string: name, attributes: [
                .foregroundColor: NSColor.linkColor,
                .font: linkFont,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ])
            btn.attributedTitle = attrTitle
            btn.url = URL(string: urlStr)
            content.addSubview(btn)
        }

        let sep2 = NSBox(frame: NSRect(x: 40, y: 58, width: 240, height: 1))
        sep2.boxType = .separator
        content.addSubview(sep2)

        let licenseField = NSTextField(labelWithString: "License: MIT")
        licenseField.font = .systemFont(ofSize: 11)
        licenseField.textColor = .tertiaryLabelColor
        licenseField.alignment = .center
        licenseField.frame = NSRect(x: 0, y: 32, width: 320, height: 16)
        content.addSubview(licenseField)

        let closeBtn = NSButton(title: "Close", target: panel, action: #selector(NSWindow.close))
        closeBtn.setFrameOrigin(NSPoint(x: 130, y: 8))
        closeBtn.bezelStyle = .push
        content.addSubview(closeBtn)

        panel.contentView = content
        panel.level = .modalPanel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    final class URLButton: NSButton {
        var url: URL?
    }

    @objc func openContributorURL(_ sender: NSButton) {
        guard let btn = sender as? URLButton, let url = btn.url else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Session Helpers

    func sessionMenuLine(_ s: Session) -> String {
        let now = Date().timeIntervalSince1970
        let eff = s.eff.isEmpty ? effectiveState(s, now: now) : s.eff
        let actStart = sessionActiveStart[s.id] ?? s.startedAt
        var line = truncated(sessionName(s))
        if eff == "thinking" || eff == "tool", actStart > 0 {
            line += "  " + elapsed(max(0, Int(now - actStart)))
        }
        return line
    }

    func uiConfig() -> [String: Double] {
        let p = (NSHomeDirectory() as NSString).appendingPathComponent(".config/opencode/statusbar/uiconfig.json")
        guard let d = FileManager.default.contents(atPath: p),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        return j.compactMapValues { ($0 as? NSNumber)?.doubleValue }
    }

    func configureSessionRow(_ v: SessionRowView, _ s: Session, eff: String) {
        let cfg = uiConfig()
        let now = Date().timeIntervalSince1970
        let nameMax = loadedConfig.display?.nameMax ?? Int(cfg["nameMax"] ?? 16)
        let actStart = sessionActiveStart[s.id] ?? s.startedAt
        let working = (eff == "thinking" || eff == "tool") && actStart > 0
        let resting = !(eff == "permission" || eff == "thinking" || eff == "tool")
        let tag = surfaceTag(s.entrypoint)
        v.configure(icon: sessionSymbol(s, eff: eff),
                    iconTint: resting ? .tertiaryLabelColor : .labelColor,
                    name: truncated(sessionName(s), max: nameMax, keep: nameMax),
                    timer: working ? elapsed(max(0, Int(now - actStart))) : nil,
                    pillNormal: tag.isEmpty ? nil : pillImage(tag),
                    pillSelected: tag.isEmpty ? nil : pillImage(tag, selected: true),
                    pillInset: CGFloat(cfg["pillInset"] ?? 12),
                    timerGap: CGFloat(cfg["timerGap"] ?? 10))
    }

    func statusText(_ s: Session, eff: String) -> String {
        switch eff {
        case "permission":
            return configLabel("permission") ?? configLabel("waiting") ?? "Waiting permission"
        case "thinking", "tool":
            return workingLabel(s)
        default:
            let idleLabel = configLabel("idle") ?? "Idle"
            let doneLabel = configLabel("done") ?? "Done"
            return s.state == "done" ? doneLabel : idleLabel
        }
    }

    func sessionName(_ s: Session) -> String {
        s.project.isEmpty ? "session" : s.project
    }

    func surfaceTag(_ entrypoint: String) -> String {
        switch entrypoint {
        case "opencode-desktop": return "APP"
        case "":                 return ""
        default:                 return "CLI"
        }
    }

    func pillImage(_ text: String, selected: Bool = false) -> NSImage {
        let t = text as NSString
        let font = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .semibold)
        let pad: CGFloat = 7, h: CGFloat = 15
        let cfg = uiConfig()
        let dy = CGFloat(cfg["pillTextY"] ?? -1)
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let bgAlpha = CGFloat(cfg[dark ? "pillBgDark" : "pillBgLight"] ?? (dark ? 0.14 : 0.10))
        let bg = selected ? NSColor.white.withAlphaComponent(0.22)
                          : (dark ? NSColor.white : NSColor.black).withAlphaComponent(bgAlpha)
        let fg = selected ? NSColor.white : NSColor.labelColor
        let w = ceil(t.size(withAttributes: [.font: font]).width) + pad * 2
        return NSImage(size: NSSize(width: w, height: h), flipped: false) { rect in
            bg.setFill()
            NSBezierPath(roundedRect: rect, xRadius: h / 2, yRadius: h / 2).fill()
            let a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: fg]
            let ts = t.size(withAttributes: a)
            t.draw(at: NSPoint(x: (rect.width - ts.width) / 2, y: (rect.height - ts.height) / 2 + dy), withAttributes: a)
            return true
        }
    }

    func sessionSymbol(_ s: Session, eff: String) -> NSImage? {
        switch eff {
        case "permission":
            let tint = effectiveColor(for: "permission") ?? amber
            return symbolImage("exclamationmark.circle.fill", tint: tint)
        case "thinking", "tool": return rotatedSpinner(spinAngle)
        default:                 return restingIcon(color: nil)
        }
    }

    lazy var restingCaret: NSImage? = {
        let glyph = "\u{276F}" as NSString
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let side = spinnerBase?.size.width ?? 15
        let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
            let g = glyph.size(withAttributes: attrs)
            glyph.draw(at: NSPoint(x: (side - g.width) / 2, y: (side - g.height) / 2), withAttributes: attrs)
            return true
        }
        img.isTemplate = true
        return img
    }()

    lazy var spinnerBase: NSImage? = {
        let name: String
        if #available(macOS 15.0, *) { name = "progress.indicator" } else { name = "rays" }
        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        guard let sym = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) else { return nil }
        let side = ceil(max(sym.size.width, sym.size.height)) + 2
        let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            sym.draw(in: NSRect(x: (side - sym.size.width) / 2, y: (side - sym.size.height) / 2,
                                width: sym.size.width, height: sym.size.height))
            return true
        }
        img.isTemplate = true
        return img
    }()

    func rotatedSpinner(_ angleDeg: CGFloat) -> NSImage? {
        guard let base = spinnerBase else { return nil }
        let size = base.size
        let img = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.translateBy(x: size.width / 2, y: size.height / 2)
            ctx.rotate(by: -angleDeg * .pi / 180)
            ctx.translateBy(x: -size.width / 2, y: -size.height / 2)
            base.draw(in: rect)
            return true
        }
        img.isTemplate = true
        return img
    }

    func symbolImage(_ name: String, tint: NSColor? = nil) -> NSImage? {
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        if let tint = tint, #available(macOS 12.0, *) {
            return img.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [tint]))
        }
        img.isTemplate = true
        return img
    }

    func truncated(_ s: String, max: Int = 20, keep: Int = 18) -> String {
        s.count > max ? String(s.prefix(keep)) + "…" : s
    }

    func priority(of eff: String) -> Int {
        switch eff {
        case "permission":       return 2
        case "thinking", "tool": return 1
        default:                 return 0
        }
    }

    func workingLabel(_ s: Session) -> String {
        if let custom = configLabel("thinking"), !custom.isEmpty { return custom }
        if !s.label.isEmpty { return s.label }
        return s.state == "tool" ? "Working…" : "Thinking…"
    }

    func elapsed(_ secs: Int) -> String {
        let m = secs / 60, s = secs % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }

    @objc func quit() { NSApp.terminate(nil) }

    @objc func openOpencode() {
        let ws = NSWorkspace.shared
        if let url = ws.urlForApplication(withBundleIdentifier: "com.anomaly.opencodedesktop") {
            ws.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func openSession(_ id: String, entrypoint: String, termProgram: String) {
        if entrypoint == "opencode-desktop" { openOpencode(); return }
        let app: String
        switch termProgram {
        case "Apple_Terminal": app = "Terminal"
        case "iTerm.app":      app = "iTerm"
        case "vscode":         app = "Visual Studio Code"
        case "WarpTerminal":   app = "Warp"
        case "":               return
        default:               app = termProgram
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", app]
        try? p.run()
    }

    @objc func chooseHideIdle(_ sender: NSMenuItem) {
        guard let secs = sender.representedObject as? Double else { return }
        UserDefaults.standard.set(secs, forKey: "hideIdleAfter")
        if loadedConfig.display == nil { loadedConfig.display = SBConfig.DisplayConfig() }
        loadedConfig.display?.hideIdleAfter = secs
        saveConfig()
    }

    @objc func chooseStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let st = AnimStyle(rawValue: raw) else { return }
        animStyle = st
        UserDefaults.standard.set(raw, forKey: "animStyle")
        animTimer?.invalidate(); animTimer = nil
        frameIdx = 0
        pulseFrame = 0
        evaluate()
    }

    @objc func chooseSystemStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        systemStyle = raw
        UserDefaults.standard.set(raw, forKey: "systemStyle")
        if let menu = statusItem.menu { populateMenu(menu) }
    }

    @objc func chooseMinDuration(_ sender: NSMenuItem) {
        guard let val = sender.representedObject as? Double else { return }
        soundMinDuration = val
        UserDefaults.standard.set(val, forKey: "soundMinDuration")
        if loadedConfig.sound == nil { loadedConfig.sound = SBConfig.SoundConfig() }
        loadedConfig.sound?.minDuration = val
        saveConfig()
        if let menu = statusItem.menu { populateMenu(menu) }
    }

    // MARK: Break Time

    @objc func toggleBreak(_ sender: Any) {
        breakEnabled.toggle()
        UserDefaults.standard.set(breakEnabled, forKey: "breakEnabled")
        if loadedConfig.breakTime == nil { loadedConfig.breakTime = SBConfig.BreakConfig() }
        loadedConfig.breakTime?.enabled = breakEnabled
        saveConfig()
        if breakEnabled { startBreakTimer() } else { cancelBreakTimer() }
        if let menu = statusItem.menu { populateMenu(menu) }
    }

    @objc func chooseBreakInterval(_ sender: NSMenuItem) {
        guard let val = sender.representedObject as? Double else { return }
        breakInterval = max(val, 1)
        UserDefaults.standard.set(breakInterval, forKey: "breakInterval")
        if loadedConfig.breakTime == nil { loadedConfig.breakTime = SBConfig.BreakConfig() }
        loadedConfig.breakTime?.interval = breakInterval
        saveConfig()
        startBreakTimer()
        if let menu = statusItem.menu { populateMenu(menu) }
    }

    @objc func chooseCustomInterval() {
        let alert = NSAlert()
        alert.messageText = "Custom Break Interval"
        alert.informativeText = "Enter interval in minutes:"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        field.placeholderString = "e.g. 90"
        field.stringValue = "\(Int(breakInterval / 60))"
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard let mins = Double(trimmed), mins >= 1 else { return }
        breakInterval = mins * 60
        UserDefaults.standard.set(breakInterval, forKey: "breakInterval")
        if loadedConfig.breakTime == nil { loadedConfig.breakTime = SBConfig.BreakConfig() }
        loadedConfig.breakTime?.interval = breakInterval
        saveConfig()
        startBreakTimer()
        if let menu = statusItem.menu { populateMenu(menu) }
    }

    @objc func chooseBreakDuration(_ sender: NSMenuItem) {
        guard let val = sender.representedObject as? Double else { return }
        breakDuration = val
        UserDefaults.standard.set(val, forKey: "breakDuration")
        if loadedConfig.breakTime == nil { loadedConfig.breakTime = SBConfig.BreakConfig() }
        loadedConfig.breakTime?.duration = val
        saveConfig()
        if let menu = statusItem.menu { populateMenu(menu) }
    }

    func startBreakTimer() {
        cancelBreakTimer()
        guard breakEnabled, breakInterval > 0 else { return }
        if breakAudioOnly {
            breakTimer = Timer.scheduledTimer(withTimeInterval: breakInterval, repeats: true) { [weak self] _ in
                self?.playBreakAudio()
            }
        } else {
            breakTimer = Timer.scheduledTimer(withTimeInterval: breakInterval, repeats: false) { [weak self] _ in
                self?.showBreak()
            }
        }
    }

    func playBreakAudio() {
        if let path = loadedConfig.sound?.breakOnlyPath, !path.isEmpty,
           FileManager.default.fileExists(atPath: path) {
            breakAudioPlayer = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            breakAudioPlayer?.prepareToPlay()
        } else if breakAudioPlayer == nil {
            if let path = Bundle.main.path(forResource: "tic-toc", ofType: "wav") {
                breakAudioPlayer = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
                breakAudioPlayer?.prepareToPlay()
            }
        }
        breakAudioPlayer?.currentTime = 0
        breakAudioPlayer?.volume = 1.0
        breakAudioPlayer?.play()
    }

    func cancelBreakTimer() {
        breakTimer?.invalidate()
        breakTimer = nil
    }

    func showBreak() {
        guard !breakActive else { return }
        breakActive = true
        breakCountdown = Int(breakDuration)
        if breakCountdown < 1 { breakCountdown = 1 }

        if let path = loadedConfig.sound?.breakStartPath, !path.isEmpty,
           FileManager.default.fileExists(atPath: path),
           let p = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path)) {
            p.volume = 1.0
            p.play()
        } else {
            NSSound(named: "Tink")?.play()
        }

        countPlayer?.stop()
        if let path = Bundle.main.path(forResource: "count", ofType: "mp3") {
            countPlayer = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
        }
        countPlayer?.volume = 1.0

        breakIconIndex = Int.random(in: 0..<breakIcons.count)
        let bTitle = configLabel("breakTitle") ?? defaultLabel(for: "breakTitle")
        let bMsg = configLabel("breakMessage") ?? defaultLabel(for: "breakMessage")
        let cnt = breakIcons.count
        let carIcons = (0..<5).map { i -> String in
            let idx = (breakIconIndex + i - 2 + cnt) % cnt
            return breakIcons[idx]
        }

        let screens = NSScreen.screens
        for screen in screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false

            let view = BreakView(frame: screen.frame)
            view.setCarousel(carIcons)
            view.show(title: bTitle, count: breakCountdown, message: bMsg)
            view.onSkip = { [weak self] in self?.hideBreak() }
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            breakWindows.append(window)
        }

        if let km = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged], handler: { _ in nil }) {
            breakEventMonitors.append(km)
        }

        breakCountdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.breakTick()
        }
    }

    func hideBreak() {
        guard breakActive else { return }
        breakActive = false
        breakCountdownTimer?.invalidate()
        breakCountdownTimer = nil
        for m in breakEventMonitors { NSEvent.removeMonitor(m) }
        breakEventMonitors = []
        breakWindows.forEach { $0.orderOut(nil) }
        breakWindows.removeAll()
        countPlayer?.stop()
        if let path = loadedConfig.sound?.breakCompletePath, !path.isEmpty,
           FileManager.default.fileExists(atPath: path),
           let p = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path)) {
            p.volume = 1.0
            p.play()
        } else {
            playCompletionChime()
        }
        startBreakTimer()
    }

    func breakTick() {
        guard breakActive else { return }
        breakCountdown -= 1
        breakIconIndex = (breakIconIndex + 1) % breakIcons.count
        let newIcon = breakIcons[(breakIconIndex + 2) % breakIcons.count]
        for w in breakWindows {
            let v = w.contentView as? BreakView
            v?.updateCountdown(breakCountdown)
            v?.slideCarousel(newIcon: newIcon)
        }
        countPlayer?.currentTime = 0
        countPlayer?.play()
        if breakCountdown <= 0 {
            breakCountdownTimer?.invalidate()
            breakCountdownTimer = nil
            hideBreak()
        }
    }

    // MARK: SMC Temperature

    struct SMCParam {
        var key: UInt32 = 0
        var vMaj: UInt8 = 0; var vMin: UInt8 = 0; var vBld: UInt8 = 0; var vRsv: UInt8 = 0; var vRel: UInt16 = 0
        var _pad0: UInt16 = 0
        var plVer: UInt16 = 0; var plLen: UInt16 = 0; var plCPU: UInt32 = 0; var plGPU: UInt32 = 0; var plMem: UInt32 = 0
        var dSize: UInt32 = 0; var dType: UInt32 = 0; var dAttr: UInt8 = 0
        var _pad1: UInt8 = 0; var _pad2: UInt8 = 0; var _pad3: UInt8 = 0
        var r: UInt8 = 0; var s: UInt8 = 0; var d8: UInt8 = 0; var _pad4: UInt8 = 0; var d32: UInt32 = 0
        var b0: UInt8 = 0; var b1: UInt8 = 0; var b2: UInt8 = 0; var b3: UInt8 = 0
        var b4: UInt8 = 0; var b5: UInt8 = 0; var b6: UInt8 = 0; var b7: UInt8 = 0
        var b8: UInt8 = 0; var b9: UInt8 = 0; var b10: UInt8 = 0; var b11: UInt8 = 0
        var b12: UInt8 = 0; var b13: UInt8 = 0; var b14: UInt8 = 0; var b15: UInt8 = 0
        var b16: UInt8 = 0; var b17: UInt8 = 0; var b18: UInt8 = 0; var b19: UInt8 = 0
        var b20: UInt8 = 0; var b21: UInt8 = 0; var b22: UInt8 = 0; var b23: UInt8 = 0
        var b24: UInt8 = 0; var b25: UInt8 = 0; var b26: UInt8 = 0; var b27: UInt8 = 0
        var b28: UInt8 = 0; var b29: UInt8 = 0; var b30: UInt8 = 0; var b31: UInt8 = 0
    }

    func readTemperature() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        var conn: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == KERN_SUCCESS else {
            IOObjectRelease(service); return nil
        }
        IOObjectRelease(service)
        defer { IOServiceClose(conn) }

        for keyStr in ["TC0P", "TC01", "TC0D", "Tp09", "Tp01", "Tp0T", "Th0P"] {
            if let val = smcReadValue(conn: conn, key: keyStr) {
                return val
            }
        }
        return nil
    }

    func smcReadValue(conn: io_connect_t, key: String) -> Double? {
        let keyCode = key.utf8.reduce(0 as UInt32) { ($0 << 8) | UInt32($1) }.bigEndian

        // kSMCGetKeyInfo
        var input = SMCParam()
        input.key = keyCode
        input.d8 = 5

        var output = SMCParam()
        var outSize = MemoryLayout<SMCParam>.stride
        let ret = withUnsafeMutablePointer(to: &input) { inpPtr in
            withUnsafeMutablePointer(to: &output) { outPtr in
                IOConnectCallStructMethod(conn, 2, inpPtr, MemoryLayout<SMCParam>.stride, outPtr, &outSize)
            }
        }
        guard ret == KERN_SUCCESS else { return nil }

        // kSMCReadKey
        input.key = keyCode
        input.dType = output.dType
        input.dSize = output.dSize
        input.d8 = 6

        output = SMCParam()
        outSize = MemoryLayout<SMCParam>.stride
        let ret2 = withUnsafeMutablePointer(to: &input) { inpPtr in
            withUnsafeMutablePointer(to: &output) { outPtr in
                IOConnectCallStructMethod(conn, 2, inpPtr, MemoryLayout<SMCParam>.stride, outPtr, &outSize)
            }
        }
        guard ret2 == KERN_SUCCESS else { return nil }

        let dataType = output.dType.bigEndian
        let dataSize = output.dSize.bigEndian

        // sp78 format (signed 7.8 fixed point) = temperature in Celsius
        if dataType == 0x73703738 && dataSize >= 2 { // "sp78"
            let hi = UInt16(output.b0) << 8 | UInt16(output.b1)
            let isNeg = (hi & 0x8000) != 0
            let val = isNeg ? -(Double(~hi & 0x7FFF) + 1) : Double(hi)
            return val / 256.0
        }
        // flt format (float)
        if dataType == 0x666C7420 && dataSize >= 4 { // "flt "
            let bits = UInt32(output.b0) << 24 | UInt32(output.b1) << 16 | UInt32(output.b2) << 8 | UInt32(output.b3)
            return Double(Float(bitPattern: bits))
        }
        return nil
    }

    // MARK: State Polling

    func updateSystemStats() {
        ramTotal = ProcessInfo.processInfo.physicalMemory
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64_data_t()
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        if kr == KERN_SUCCESS {
            let pageSize = UInt64(vm_page_size)
            let active = UInt64(stats.active_count)
            let wired = UInt64(stats.wire_count)
            let compressed = UInt64(stats.compressor_page_count)
            ramUsed = (active + wired + compressed) * pageSize
        }

        // Per-core CPU
        var cpuCount = natural_t(0)
        var cpuInfoPtr: processor_info_array_t? = nil
        var cpuInfoCnt = mach_msg_type_number_t(0)
        let kr3 = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &cpuInfoPtr, &cpuInfoCnt)
        if kr3 == KERN_SUCCESS, let info = cpuInfoPtr {
            cpuCores = Int(cpuCount)
            let totalCount = Int(cpuInfoCnt)
            var cur: [(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)] = []
            let stride = Int(CPU_STATE_MAX)
            for i in 0..<Int(cpuCount) {
                let base = i * stride
                guard base + 3 < totalCount else { continue }
                let u   = UInt32(info[base + Int(CPU_STATE_USER)])
                let s   = UInt32(info[base + Int(CPU_STATE_SYSTEM)])
                let idl = UInt32(info[base + Int(CPU_STATE_IDLE)])
                let n   = UInt32(info[base + Int(CPU_STATE_NICE)])
                cur.append((u, s, idl, n))
            }
            if let prev = prevCoreTicksArray, prev.count == cur.count {
                perCoreUsage = zip(cur, prev).map { c, p in
                    let totalDelta = (c.user - p[0]) + (c.system - p[1]) + (c.idle - p[2]) + (c.nice - p[3])
                    let idleDelta = c.idle - p[2]
                    return totalDelta > 0 ? Double(totalDelta - idleDelta) / Double(totalDelta) * 100 : 0
                }
            } else {
                perCoreUsage = Array(repeating: 0, count: cur.count)
            }
            prevCoreTicksArray = cur.map { [$0.user, $0.system, $0.idle, $0.nice] }
            cpuUsage = perCoreUsage.reduce(0, +) / Double(max(perCoreUsage.count, 1))
        }

        temperature = readTemperature()

        // Multiple disks — all local non-system volumes
        disks.removeAll()
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsLocalKey, .volumeIsRootFileSystemKey]
        if let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys) {
            for vol in volumes {
                guard let vals = try? vol.resourceValues(forKeys: Set(keys)),
                      let name = vals.volumeName,
                      let isLocal = vals.volumeIsLocal, isLocal else { continue }
                let path = vol.path
                // exclude system/pseudo/snapshot volumes
                guard !path.hasPrefix("/System/"),
                      !path.hasPrefix("/private/"),
                      !path.contains("/.timemachine/"),
                      !name.lowercased().hasPrefix("backups of"),
                      !name.contains("@snap-") else { continue }
                guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: path) else { continue }
                let free  = (attrs[FileAttributeKey.systemFreeSize] as? UInt64) ?? 0
                let total = (attrs[FileAttributeKey.systemSize]     as? UInt64) ?? 0
                // skip pseudo/tiny volumes (< 1 GB)
                guard total >= 1_073_741_824 else { continue }
                let isInternal = (path == "/" || (vals.volumeIsRootFileSystem == true))
                let type = diskType(forPath: path)
                disks.append((name, free, total, isInternal, type))
            }
        }
        // always have / as fallback
        if disks.isEmpty, let rootAttrs = try? FileManager.default.attributesOfFileSystem(forPath: "/") {
            let rootFree  = (rootAttrs[FileAttributeKey.systemFreeSize] as? UInt64) ?? 0
            let rootTotal = (rootAttrs[FileAttributeKey.systemSize]     as? UInt64) ?? 0
            disks.append(("/", rootFree, rootTotal, true, "SSD"))
        }
        diskFree  = disks.first?.free  ?? 0
        diskTotal = disks.first?.total ?? 0
    }

    func tick() {
        reloadConfigIfNeeded()
        checkLifecycle()
        reloadSessions()
        evaluate()
        updateSystemStats()
        if menuIsOpen { refreshOpenMenuRows() }
    }

    func stateFileNames() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: stateDir)) ?? []).filter { $0.hasSuffix(".json") }
    }

    func reloadSessions() {
        let fm = FileManager.default
        let files = stateFileNames()
        let present = Set(files)
        for key in Array(fileMTimes.keys) where !present.contains(key) {
            fileMTimes[key] = nil
            sessions[(key as NSString).deletingPathExtension] = nil
        }
        for f in files {
            let full = (stateDir as NSString).appendingPathComponent(f)
            guard let attrs = try? fm.attributesOfItem(atPath: full),
                  let m = attrs[.modificationDate] as? Date else { continue }
            if fileMTimes[f] == m { continue }
            fileMTimes[f] = m
            guard let data = fm.contents(atPath: full),
                  let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let id = (f as NSString).deletingPathExtension
            sessions[id] = Session(json: o, id: id)
        }
    }

    func evaluate() {
        let now = Date().timeIntervalSince1970
        var chime = false
        var notif = false

        for id in Array(sessions.keys) {
            guard var s = sessions[id] else { continue }
            s.eff = effectiveState(s, now: now)
            let dead = s.pid > 0 ? !pidAlive(s.pid)
                                 : (s.eff == "idle" && stalePruneAge > 0 && now - s.ts > stalePruneAge)
            if dead {
                try? FileManager.default.removeItem(atPath: (stateDir as NSString).appendingPathComponent(id + ".json"))
                sessions[id] = nil; fileMTimes[id + ".json"] = nil; soundPrev[id] = nil; turnStart[id] = nil; sessionActiveStart[id] = nil
                continue
            }
            sessions[id] = s
            let isActive = (s.eff == "thinking" || s.eff == "tool" || s.eff == "permission")
            if isActive {
                if sessionActiveStart[id] == nil {
                    sessionActiveStart[id] = s.startedAt > 0 ? s.startedAt : now
                }
            } else {
                sessionActiveStart[id] = nil
            }
            if notifEdge(s) { notif = true }
            if soundEdgeDone(s, now: now) { chime = true }
        }
        for id in Array(soundPrev.keys) where sessions[id] == nil { soundPrev[id] = nil; turnStart[id] = nil; sessionActiveStart[id] = nil }
        if chime { playCompletionChime() }
        if notif { playNotifChime() }

        let lead = sessions.values.max { a, b in
            let pa = priority(of: a.eff), pb = priority(of: b.eff)
            return pa == pb ? a.ts < b.ts : pa < pb
        }
        statusItem.button?.toolTip = lead.map(sessionMenuLine)

        guard let lead = lead else { renderResting(); return }
        switch lead.eff {
        case "permission":
            forcePulse = true
            render(label: statusText(lead, eff: lead.eff), color: effectiveColor(for: "permission") ?? amber, animate: true, startedAt: 0)
        case "thinking", "tool":
            forcePulse = false
            render(label: statusText(lead, eff: lead.eff), color: effectiveColor(for: lead.eff), animate: true, startedAt: sessionActiveStart[lead.id] ?? lead.startedAt)
        default:
            renderResting()
        }
    }

    func renderResting() {
        if let custom = customIconImage() {
            statusItem.button?.image = custom
            statusItem.button?.title = ""
            return
        }
        render(label: "", color: effectiveColor(for: "idle"), animate: false, startedAt: 0)
    }

    func effectiveState(_ s: Session, now: Double) -> String {
        if s.state == "thinking" || s.state == "tool" || s.state == "permission" {
            let cap: Double = s.state == "permission" ? 7200 : 900
            if now - s.ts > cap { return "idle" }
            if !s.transcript.isEmpty, let last = lastTurnLine(ofFileAt: s.transcript),
               last.contains("interrupted by user") { return "idle" }
            return s.state
        }
        return s.state == "done" ? "idle" : s.state
    }

    func soundEdgeDone(_ s: Session, now: Double) -> Bool {
        let prev = soundPrev[s.id] ?? ""
        if s.eff == "thinking" || s.eff == "tool", s.startedAt > 0, (turnStart[s.id] ?? 0) == 0 { turnStart[s.id] = s.startedAt }
        var edge = false
        let isNowIdle = s.eff == "idle" || s.eff.isEmpty
        let wasBusy = prev == "thinking" || prev == "tool"
        if wasBusy && isNowIdle, let st = turnStart[s.id], st > 0, now - st >= soundMinDuration { edge = true }
        if isNowIdle { turnStart[s.id] = 0 }
        soundPrev[s.id] = s.eff
        return edge
    }

    func notifEdge(_ s: Session) -> Bool {
        guard playNotifSound else { return false }
        let prev = soundPrev[s.id] ?? ""
        return s.eff == "permission" && prev != "permission"
    }

    // MARK: Lifecycle

    func opencodeDesktopRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == opencodeDesktopBundleID }
    }

    func opencodeProcessRunning() -> Bool {
        !stateFileNames().isEmpty || !((try? FileManager.default.contentsOfDirectory(atPath: stateDir)) ?? []).isEmpty
    }

    func sessionCount() -> Int { stateFileNames().count }

    func pidAlive(_ pid: Int32) -> Bool {
        if pid <= 0 { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    func checkLifecycle() {
        // Status bar app stays alive
    }

    func lastLine(ofFileAt path: String) -> String? {
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        let chunk: UInt64 = 8192
        try? fh.seek(toOffset: size > chunk ? size - chunk : 0)
        guard let data = try? fh.readToEnd(), let s = String(data: data, encoding: .utf8) else { return nil }
        return s.split(separator: "\n").last { !$0.isEmpty }.map(String.init)
    }

    func lastTurnLine(ofFileAt path: String) -> String? {
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        let chunk: UInt64 = 8192
        try? fh.seek(toOffset: size > chunk ? size - chunk : 0)
        guard let data = try? fh.readToEnd(), let s = String(data: data, encoding: .utf8) else { return nil }
        return s.split(separator: "\n").last {
            $0.contains("\"type\":\"user\"") || $0.contains("\"type\":\"assistant\"")
        }.map(String.init)
    }

    // MARK: Render

    func render(label: String, color: NSColor?, animate: Bool, startedAt: Double, dot: Bool = false) {
        guard let button = statusItem.button else { return }
        button.contentTintColor = nil
        activeBase = label
        activeColor = color
        self.startedAt = startedAt

        if animate {
            if animTimer == nil {
                let t = Timer(timeInterval: 1.0 / fps, repeats: true) { [weak self] _ in self?.animStep() }
                RunLoop.main.add(t, forMode: .common)
                animTimer = t
            }
        } else {
            animTimer?.invalidate(); animTimer = nil
            frameIdx = 0
            pulseFrame = 0
            button.image = dot ? dotIcon(color: color) : restingIcon(color: color)
        }
        applyTitle()
        if button.image == nil { button.image = dot ? dotIcon(color: color) : restingIcon(color: color) }
    }

    func animStep() {
        frameIdx = (frameIdx + 1) % frameCount
        if forcePulse {
            pulseFrame += 1
            statusItem.button?.image = pulseIcon(frame: pulseFrame, color: activeColor)
        } else {
            statusItem.button?.image = iconImage(color: activeColor, frame: frameIdx)
        }
        applyTitle()
    }

    func applyTitle() {
        var t = activeBase
        if showTimer, startedAt > 0 {
            let secs = Int(Date().timeIntervalSince1970 - startedAt)
            if secs > 0 { t = activeBase.isEmpty ? elapsed(secs) : activeBase + " " + elapsed(secs) }
        }
        guard let button = statusItem.button else { return }
        if let color = activeColor, !t.isEmpty {
            button.attributedTitle = NSAttributedString(string: t, attributes: [
                .foregroundColor: color,
                .font: button.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
            ])
        } else {
            button.attributedTitle = NSAttributedString(string: "")
            button.title = t
        }
    }

    func restingIcon(color: NSColor?) -> NSImage? {
        if let custom = customIconImage() { return custom }
        let side: CGFloat = 18
        let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let r = rect.insetBy(dx: 3, dy: 3)
            ctx.setLineWidth(2)
            NSColor.black.setStroke()
            ctx.stroke(r)
            let inner = r.insetBy(dx: 3, dy: 3)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fill(CGRect(x: inner.minX, y: inner.midY, width: inner.width, height: inner.height / 2))
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.4).cgColor)
            ctx.fill(CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: inner.height / 2))
            return true
        }
        img.isTemplate = true
        return img
    }

    func dotIcon(color: NSColor?) -> NSImage? {
        let side: CGFloat = 18
        let c = color ?? amber
        let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            c.setFill()
            ctx.fillEllipse(in: rect.insetBy(dx: 3, dy: 3))
            return true
        }
        return img
    }

    func iconImage(color: NSColor?, frame: Int) -> NSImage? {
        switch animStyle {
        case .spark:
            return sparkIcon(frame: frame, color: color)
        case .block:
            return resizeImage(blockFrames[frame % blockFrames.count], color: color)
        case .term:
            let glyphIdx = (frame / termSub) % termGlyphs.count
            let progress = CGFloat(frame % termSub) / CGFloat(termSub)
            return animatedGlyph(glyphIdx, progress: progress, color: color)
        case .bounce:
            return bounceIcon(frame: frame, color: color)
        case .pulse:
            return pulseIcon(frame: frame, color: color)
        case .dots:
            return dotsIcon(frame: frame, color: color)
        case .basic:
            return basicIcon(frame: frame, color: color)
        }
    }

    // MARK: Spark Animation

    func sparkIcon(frame: Int, color: NSColor?) -> NSImage? {
        let side: CGFloat = 18
        let total = sparkFrameCount
        let f = CGFloat(frame % total) / CGFloat(total)
        let inset: CGFloat = 2
        let r = CGRect(x: inset, y: inset, width: side - 2*inset, height: side - 2*inset)
        let w = r.width, h = r.height
        let perim = 2 * (w + h)
        let dist = f * perim

        var dotX: CGFloat, dotY: CGFloat
        if dist < w {
            dotX = r.minX + dist
            dotY = r.minY
        } else if dist < w + h {
            dotX = r.maxX
            dotY = r.minY + (dist - w)
        } else if dist < 2 * w + h {
            dotX = r.maxX - (dist - w - h)
            dotY = r.maxY
        } else {
            dotX = r.minX
            dotY = r.maxY - (dist - 2*w - h)
        }

        let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            NSColor.black.withAlphaComponent(0.3).setStroke()
            ctx.setLineWidth(1.5)
            ctx.stroke(r)
            NSColor.black.setFill()
            let dotR: CGFloat = 2.5
            ctx.fillEllipse(in: CGRect(x: dotX - dotR, y: dotY - dotR, width: dotR * 2, height: dotR * 2))
            return true
        }
        img.isTemplate = true
        return img
    }

    // MARK: Bounce Animation

    func bounceIcon(frame: Int, color: NSColor?) -> NSImage? {
        let side: CGFloat = 18
        let total = 16
        let progress = CGFloat(frame % total) / CGFloat(total)
        let amplitude: CGFloat = 4.5
        let yOffset = sin(progress * .pi * 2) * amplitude
        let dotR: CGFloat = 3

        let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let cx = rect.midX
            let cy = rect.midY + yOffset
            NSColor.black.setFill()
            ctx.fillEllipse(in: CGRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2))
            return true
        }
        img.isTemplate = true
        return img
    }

    // MARK: Pulse Animation

    func pulseIcon(frame: Int, color: NSColor?) -> NSImage? {
        let side: CGFloat = 18
        let total = 48
        let t = CGFloat(frame % total) / CGFloat(total)
        let breath = sin(t * .pi)
        let maxR: CGFloat = 6
        let r = maxR * (0.45 + breath * 0.55)
        let alpha: CGFloat = 0.25 + breath * 0.75
        let c = color ?? amber

        let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let cx = rect.midX, cy = rect.midY
            c.withAlphaComponent(alpha).setFill()
            ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            return true
        }
        img.isTemplate = false
        return img
    }

    // MARK: Dots Animation

    func dotsIcon(frame: Int, color: NSColor?) -> NSImage? {
        let side: CGFloat = 18
        let total = 12
        let phase = (frame % total) / 4
        let dotR: CGFloat = 2
        let spacing: CGFloat = 6
        let baseX: CGFloat = (side - spacing * 2) / 2

        let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let cy = rect.midY
            for i in 0..<3 {
                let alpha: CGFloat = i == phase ? 1.0 : 0.25
                let cx = baseX + CGFloat(i) * spacing
                NSColor.black.withAlphaComponent(alpha).setFill()
                ctx.fillEllipse(in: CGRect(x: cx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2))
            }
            return true
        }
        img.isTemplate = true
        return img
    }

    // MARK: Basic Animation

    func basicIcon(frame: Int, color: NSColor?) -> NSImage? {
        let side: CGFloat = 18
        let total = 60
        let progress = CGFloat(frame % total) / CGFloat(total)
        let t = sin(progress * .pi)
        let minSplit: CGFloat = 0.3
        let maxSplit: CGFloat = 0.7
        let splitRatio = minSplit + (maxSplit - minSplit) * t

        let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            let isDark = NSApp.effectiveAppearance.name == .darkAqua

            let bgColor = (isDark ? NSColor.black : NSColor(white: 0.949, alpha: 1)).cgColor
            let topColor = (isDark ? NSColor(white: 0.961, alpha: 1) : NSColor(white: 0.067, alpha: 1)).cgColor
            let bottomColor = (isDark ? NSColor(white: 0.741, alpha: 1) : NSColor(white: 0.561, alpha: 1)).cgColor

            let inset: CGFloat = 3
            let container = rect.insetBy(dx: inset, dy: inset)
            let cornerRadius: CGFloat = 4

            let path = CGPath(roundedRect: container, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            ctx.addPath(path)
            ctx.clip()

            ctx.setFillColor(bgColor)
            ctx.fill(container)

            let splitY = container.minY + container.height * splitRatio

            ctx.setFillColor(topColor)
            ctx.fill(CGRect(x: container.minX, y: splitY, width: container.width, height: container.maxY - splitY))

            ctx.setFillColor(bottomColor)
            ctx.fill(CGRect(x: container.minX, y: container.minY, width: container.width, height: splitY - container.minY))

            return true
        }
        return img
    }

    // MARK: Shared Helpers

    func resizeImage(_ img: NSImage, color: NSColor?) -> NSImage? {
        let side: CGFloat = 18
        let resized = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            img.draw(in: rect)
            return true
        }
        resized.isTemplate = true
        return resized
    }

    func animatedGlyph(_ idx: Int, progress: CGFloat, color: NSColor?) -> NSImage? {
        let side: CGFloat = 18
        let glyph = termGlyphs[idx]
        let alpha = 0.3 + (1.0 - abs(progress - 0.5) * 2) * 0.7
        let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)
        let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard NSGraphicsContext.current != nil else { return false }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.black.withAlphaComponent(alpha),
            ]
            (glyph as NSString).draw(at: NSPoint(x: 1, y: 1), withAttributes: attrs)
            return true
        }
        img.isTemplate = true
        return img
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: StatusController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller = StatusController()
    }
}

// MARK: Break View

class BreakView: NSView {
    private let titleField = NSTextField(labelWithString: "")
    private let countField = NSTextField(labelWithString: "")
    private let msgField = NSTextField(labelWithString: "")
    private let skipButton = NSButton(title: "Skip Break", target: nil, action: nil)
    var onSkip: (() -> Void)?

    private var slots: [NSTextField] = []
    private var headIdx = 0

    override init(frame: NSRect) {
        super.init(frame: frame)

        titleField.font = .boldSystemFont(ofSize: 32)
        titleField.alignment = .center
        titleField.textColor = .white
        titleField.isBezeled = false
        titleField.drawsBackground = false
        titleField.isEditable = false
        titleField.isSelectable = false

        countField.font = .monospacedSystemFont(ofSize: 72, weight: .bold)
        countField.alignment = .center
        countField.textColor = .white
        countField.isBezeled = false
        countField.drawsBackground = false
        countField.isEditable = false
        countField.isSelectable = false

        msgField.font = .systemFont(ofSize: 15)
        msgField.alignment = .center
        msgField.textColor = .secondaryLabelColor
        msgField.isBezeled = false
        msgField.drawsBackground = false
        msgField.isEditable = false
        msgField.isSelectable = false

        skipButton.bezelStyle = .rounded
        skipButton.font = .systemFont(ofSize: 14)
        skipButton.contentTintColor = .white
        skipButton.isBordered = true
        skipButton.target = self
        skipButton.action = #selector(skipTapped)

        addSubview(titleField)
        addSubview(msgField)
        addSubview(countField)
        addSubview(skipButton)

        for _ in 0..<5 {
            let f = NSTextField(labelWithString: "")
            f.font = .systemFont(ofSize: 64)
            f.alignment = .center
            f.textColor = .white
            f.isBezeled = false
            f.drawsBackground = false
            f.isEditable = false
            f.isSelectable = false
            slots.append(f)
            addSubview(f)
        }
    }

    required init?(coder: NSCoder) { nil }

    @objc private func skipTapped() { onSkip?() }

    override func draw(_ dirtyRect: NSRect) {
        let grad = NSGradient(starting: NSColor(srgbRed: 0.12, green: 0.12, blue: 0.14, alpha: 0.75),
                              ending: NSColor(srgbRed: 0.08, green: 0.08, blue: 0.1, alpha: 0.7))
        grad?.draw(in: bounds, angle: -45)
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        let cY = h * 0.5
        titleField.frame = NSRect(x: 0, y: cY + 15, width: w, height: 40)
        msgField.frame = NSRect(x: 40, y: cY - 15, width: w - 80, height: 22)
        countField.frame = NSRect(x: 0, y: h * 0.22, width: w, height: 80)
        skipButton.frame = NSRect(x: (w - 120) / 2, y: h * 0.14, width: 120, height: 28)
        layoutSlots()
    }

    private func layoutSlots() {
        for (i, slot) in slots.enumerated() {
            let vp = ((i - headIdx + 5) % 5) - 2
            let (frame, alpha) = slotFrame(vp)
            slot.frame = frame
            slot.alphaValue = alpha
        }
    }

    private func slotFrame(_ vp: Int) -> (NSRect, CGFloat) {
        let cx = bounds.width / 2
        let cy = bounds.height * 0.5 + 60
        let gap: CGFloat = 90
        let isMid = vp == 0
        let size: CGFloat = isMid ? 64 : 44
        let alpha: CGFloat = isMid ? 1.0 : (vp == -1 || vp == 1 ? 0.35 : 0)
        let x = cx + CGFloat(vp) * gap - size / 2
        return (NSRect(x: x, y: cy, width: size, height: size * 1.2), alpha)
    }

    func setCarousel(_ icons: [String]) {
        headIdx = 0
        for i in 0..<5 {
            slots[i].stringValue = i < icons.count ? icons[i] : ""
        }
        layoutSlots()
    }

    func slideCarousel(newIcon: String) {
        slots[headIdx].stringValue = newIcon
        headIdx = (headIdx + 1) % 5
        layoutSlots()
    }

    func show(title: String, count: Int, message: String) {
        titleField.stringValue = title
        countField.stringValue = "\(count)"
        msgField.stringValue = message
    }

    func updateCountdown(_ count: Int) {
        countField.stringValue = "\(count)"
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
