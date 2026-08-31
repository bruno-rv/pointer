import AppKit

@MainActor
private final class FirstUseGuideRootView: NSView {
    var onEffectiveAppearanceChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onEffectiveAppearanceChange?()
    }
}

@MainActor
public final class FirstUseGuideViewController: NSViewController {
    public struct Example: Equatable, Sendable {
        public let assetIdentifier: String
        public let shortcut: String

        public init(
            assetIdentifier: String,
            shortcut: String
        ) {
            self.assetIdentifier = assetIdentifier
            self.shortcut = shortcut
        }
    }

    public static let examples: [Example] = [
        Example(
            assetIdentifier: "arrow",
            shortcut: "Shortcut: Arrow tool"
        ),
        Example(
            assetIdentifier: "rectangle",
            shortcut: "Shortcut: Rectangle tool"
        ),
        Example(
            assetIdentifier: "ellipse",
            shortcut: "Shortcut: Ellipse tool"
        ),
        Example(
            assetIdentifier: "pen",
            shortcut: "Shortcut: Pen tool"
        ),
        Example(
            assetIdentifier: "spotlight",
            shortcut: "Shortcut: Spotlight tool"
        ),
        Example(
            assetIdentifier: "emoji",
            shortcut: "Shortcut: Emoji tool"
        ),
        Example(
            assetIdentifier: "select",
            shortcut: "Shortcut: Select tool"
        ),
        Example(
            assetIdentifier: "eraser",
            shortcut: "Shortcut: Eraser tool"
        ),
    ]

    public let assetCatalog: any GuideAssetCatalogProviding
    public let appearanceProvider: any GuideAppearanceProviding
    public var onDismiss: () -> Void
    public private(set) var titleLabel: NSTextField?
    public private(set) var explanationLabel: NSTextField?
    public private(set) var exampleImageViews: [NSImageView] = []
    public private(set) var exampleRows: [NSView] = []
    public private(set) var doneButton: NSButton?
    public private(set) var resolutionErrors: [Error] = []
    public private(set) var scrollView: NSScrollView?
    public private(set) var accessibilityOrderLabels: [String] = []

    private var focusOrder: [Any] = []
    private var resolvedImages: [String: NSImage]?
    private var resolvedVariant: GuideAssetVariant?
    private var appearanceObserverTokens: [NSObjectProtocol] = []

    public init(
        assetCatalog: any GuideAssetCatalogProviding,
        appearanceProvider: (any GuideAppearanceProviding)? = nil,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.assetCatalog = assetCatalog
        self.appearanceProvider = appearanceProvider ?? SystemGuideAppearanceProvider()
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("FirstUseGuideViewController does not support storyboards.")
    }

    func setResolvedImages(_ images: [String: NSImage], variant: GuideAssetVariant) {
        _ = commitResolvedImages(images, variant: variant)
    }

    var isAppearanceObservationActive: Bool {
        !appearanceObserverTokens.isEmpty
    }

    func startAppearanceObservation() {
        guard appearanceObserverTokens.isEmpty else { return }
        appearanceObserverTokens.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                _ = self.reloadImagesForCurrentAppearance()
            }
        })
    }

    func stopAppearanceObservation() {
        let center = NSWorkspace.shared.notificationCenter
        appearanceObserverTokens.forEach(center.removeObserver)
        appearanceObserverTokens.removeAll()
    }

    func refreshSemanticAppearance() {
        guard let root = viewIfLoaded as? FirstUseGuideRootView else { return }
        applySemanticAppearance(to: root)
    }

    private func applySemanticAppearance(to root: FirstUseGuideRootView) {
        let appearance = root.appearance ?? root.effectiveAppearance
        appearance.performAsCurrentDrawingAppearance {
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let background = isDark
                ? NSColor(calibratedWhite: 0.12, alpha: 1)
                : NSColor(calibratedWhite: 0.96, alpha: 1)
            root.layer?.backgroundColor = background.cgColor
        }
    }

    @discardableResult
    public func reloadImagesForCurrentAppearance() -> Bool {
        reloadImages(for: appearanceProvider.variant)
    }

    @discardableResult
    func reloadImages(for variant: GuideAssetVariant) -> Bool {
        let images: [String: NSImage]
        do {
            var resolved: [String: NSImage] = [:]
            for example in Self.examples {
                resolved[example.assetIdentifier] = try assetCatalog.image(
                    for: example.assetIdentifier,
                    variant: variant
                )
            }
            images = resolved
        } catch {
            resolutionErrors = [error]
            return false
        }
        return commitResolvedImages(images, variant: variant)
    }

    @discardableResult
    private func commitResolvedImages(
        _ images: [String: NSImage],
        variant: GuideAssetVariant
    ) -> Bool {
        let orderedImages = Self.examples.compactMap { images[$0.assetIdentifier] }
        guard orderedImages.count == Self.examples.count,
              !isViewLoaded || exampleImageViews.count == orderedImages.count else {
            return false
        }

        if isViewLoaded {
            for (index, image) in orderedImages.enumerated() {
                exampleImageViews[index].image = image
            }
        }
        resolvedImages = images
        resolvedVariant = variant
        resolutionErrors.removeAll()
        return true
    }

    public override func loadView() {
        let root = FirstUseGuideRootView(frame: NSRect(x: 0, y: 0, width: 440, height: 600))
        root.wantsLayer = true
        root.layer?.cornerRadius = 12
        applySemanticAppearance(to: root)
        root.setAccessibilityElement(false)

        let titleLabel = NSTextField(labelWithString: "Learn Pointer")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 22)
        titleLabel.setAccessibilityLabel("Learn Pointer")

        let explanationLabel = NSTextField(
            wrappingLabelWithString: "Draw, point, and explain what matters without changing the app beneath Pointer."
        )
        explanationLabel.maximumNumberOfLines = 0
        explanationLabel.setAccessibilityLabel("Guide explanation")
        explanationLabel.setAccessibilityHelp("A concise introduction to Pointer's annotation tools")
        self.titleLabel = titleLabel
        self.explanationLabel = explanationLabel

        let guideScrollView = NSScrollView()
        guideScrollView.hasVerticalScroller = true
        guideScrollView.autohidesScrollers = true
        guideScrollView.drawsBackground = false
        guideScrollView.borderType = .noBorder
        guideScrollView.translatesAutoresizingMaskIntoConstraints = false

        let contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 8
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        guideScrollView.documentView = contentStack

        root.addSubview(titleLabel)
        root.addSubview(explanationLabel)
        root.addSubview(guideScrollView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        explanationLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            explanationLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            explanationLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            explanationLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            guideScrollView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            guideScrollView.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            guideScrollView.topAnchor.constraint(equalTo: explanationLabel.bottomAnchor, constant: 16),
            guideScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
            guideScrollView.heightAnchor.constraint(lessThanOrEqualToConstant: 390),
            contentStack.leadingAnchor.constraint(equalTo: guideScrollView.contentView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: guideScrollView.contentView.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: guideScrollView.contentView.topAnchor),
            contentStack.widthAnchor.constraint(equalTo: guideScrollView.contentView.widthAnchor),
        ])

        scrollView = guideScrollView
        exampleImageViews.removeAll(keepingCapacity: true)
        exampleRows.removeAll(keepingCapacity: true)
        resolutionErrors.removeAll(keepingCapacity: true)
        accessibilityOrderLabels = ["Learn Pointer", "Guide explanation"]
        focusOrder = [titleLabel, explanationLabel]

        let selectedVariant = resolvedVariant ?? appearanceProvider.variant
        let images: [String: NSImage]?
        if let resolvedImages, resolvedVariant == selectedVariant {
            images = resolvedImages
        } else {
            var resolved: [String: NSImage] = [:]
            do {
                for example in Self.examples {
                    resolved[example.assetIdentifier] = try assetCatalog.image(
                        for: example.assetIdentifier,
                        variant: selectedVariant
                    )
                }
                images = resolved
                resolvedImages = resolved
                resolvedVariant = selectedVariant
            } catch {
                resolutionErrors.append(error)
                images = nil
            }
        }

        for example in Self.examples {
            let catalogEntry = assetCatalog.entries.first { $0.id == example.assetIdentifier }
            guard let catalogEntry,
                  !catalogEntry.isDecorative,
                  !catalogEntry.accessibleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !catalogEntry.accessibleDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                resolutionErrors.append(GuideAssetCatalogError.invalidMetadata(example.assetIdentifier))
                continue
            }
            let accessibleName = catalogEntry.accessibleName
            let accessibleDescription = catalogEntry.accessibleDescription
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .top
            row.spacing = 8

            let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.setAccessibilityElement(true)
            imageView.setAccessibilityLabel(accessibleName)
            imageView.setAccessibilityHelp(accessibleDescription)
            imageView.setAccessibilityRole(.image)
            imageView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: 40),
                imageView.heightAnchor.constraint(equalToConstant: 40),
            ])
            imageView.image = images?[example.assetIdentifier]

            let nameLabel = NSTextField(labelWithString: accessibleName)
            nameLabel.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
            nameLabel.setAccessibilityElement(true)
            nameLabel.setAccessibilityLabel(accessibleName)
            nameLabel.setAccessibilityHelp(accessibleDescription)

            let descriptionLabel = NSTextField(wrappingLabelWithString: accessibleDescription)
            descriptionLabel.maximumNumberOfLines = 0
            descriptionLabel.setAccessibilityElement(true)
            descriptionLabel.setAccessibilityLabel(accessibleDescription)

            let shortcutLabel = NSTextField(labelWithString: example.shortcut)
            shortcutLabel.setAccessibilityElement(true)
            shortcutLabel.setAccessibilityLabel(example.shortcut)
            shortcutLabel.setAccessibilityHelp("Essential shortcut for the \(accessibleName)")

            let textStack = NSStackView(views: [nameLabel, descriptionLabel, shortcutLabel])
            textStack.orientation = .vertical
            textStack.alignment = .leading
            textStack.spacing = 2
            row.addArrangedSubview(imageView)
            row.addArrangedSubview(textStack)
            contentStack.addArrangedSubview(row)

            exampleImageViews.append(imageView)
            exampleRows.append(row)
            focusOrder.append(contentsOf: [imageView, nameLabel, descriptionLabel, shortcutLabel])
            accessibilityOrderLabels.append(contentsOf: [
                accessibleName,
                accessibleDescription,
                example.shortcut,
            ])
        }

        let button = NSButton(title: "Done", target: self, action: #selector(done(_:)))
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        button.setAccessibilityElement(true)
        button.setAccessibilityLabel("Done")
        button.setAccessibilityHelp("Close the Pointer guide")
        button.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(button)
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            button.topAnchor.constraint(equalTo: guideScrollView.bottomAnchor, constant: 14),
            button.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
        ])
        doneButton = button
        focusOrder.append(button)
        accessibilityOrderLabels.append("Done")

        root.setAccessibilityChildren(focusOrder)
        root.onEffectiveAppearanceChange = { [weak self] in
            guard let self,
                  self.isViewLoaded,
                  self.view.window?.isVisible == true else { return }
            self.refreshSemanticAppearance()
            guard self.isAppearanceObservationActive else { return }
            _ = self.reloadImagesForCurrentAppearance()
        }
        view = root
    }

    @objc private func done(_: Any?) {
        onDismiss()
    }
}
