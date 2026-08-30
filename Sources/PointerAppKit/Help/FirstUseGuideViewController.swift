import AppKit

@MainActor
public final class FirstUseGuideViewController: NSViewController {
    public struct Example: Equatable, Sendable {
        public let assetIdentifier: String
        public let accessibleName: String
        public let accessibleDescription: String
        public let shortcut: String

        public init(
            assetIdentifier: String,
            accessibleName: String,
            accessibleDescription: String,
            shortcut: String
        ) {
            self.assetIdentifier = assetIdentifier
            self.accessibleName = accessibleName
            self.accessibleDescription = accessibleDescription
            self.shortcut = shortcut
        }
    }

    public static let examples: [Example] = [
        Example(
            assetIdentifier: "arrow",
            accessibleName: "Arrow example",
            accessibleDescription: "Arrow example — draws an attention arrow",
            shortcut: "Shortcut: Arrow tool"
        ),
        Example(
            assetIdentifier: "rectangle",
            accessibleName: "Rectangle example",
            accessibleDescription: "Rectangle example — outlines a rectangular area",
            shortcut: "Shortcut: Rectangle tool"
        ),
        Example(
            assetIdentifier: "ellipse",
            accessibleName: "Ellipse example",
            accessibleDescription: "Ellipse example — outlines an elliptical area",
            shortcut: "Shortcut: Ellipse tool"
        ),
        Example(
            assetIdentifier: "pen",
            accessibleName: "Pen example",
            accessibleDescription: "Pen example — draws a freehand line",
            shortcut: "Shortcut: Pen tool"
        ),
        Example(
            assetIdentifier: "spotlight",
            accessibleName: "Spotlight example",
            accessibleDescription: "Spotlight example — focuses attention on one area",
            shortcut: "Shortcut: Spotlight tool"
        ),
        Example(
            assetIdentifier: "emoji",
            accessibleName: "Emoji example",
            accessibleDescription: "Emoji example — stamps an emoji on the canvas",
            shortcut: "Shortcut: Emoji tool"
        ),
        Example(
            assetIdentifier: "select",
            accessibleName: "Select example",
            accessibleDescription: "Select example — selects a mark for editing",
            shortcut: "Shortcut: Select tool"
        ),
        Example(
            assetIdentifier: "eraser",
            accessibleName: "Eraser example",
            accessibleDescription: "Eraser example — removes marks as you drag",
            shortcut: "Shortcut: Eraser tool"
        ),
    ]

    public let assetCatalog: any GuideAssetCatalogProviding
    public let variant: GuideAssetVariant
    public var onDismiss: () -> Void
    public private(set) var exampleImageViews: [NSImageView] = []
    public private(set) var exampleRows: [NSView] = []
    public private(set) var doneButton: NSButton?
    public private(set) var resolutionErrors: [Error] = []

    private var focusOrder: [Any] = []

    public init(
        assetCatalog: any GuideAssetCatalogProviding,
        variant: GuideAssetVariant = .light,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.assetCatalog = assetCatalog
        self.variant = variant
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("FirstUseGuideViewController does not support storyboards.")
    }

    public override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 560))
        root.wantsLayer = true
        root.layer?.cornerRadius = 12
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
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

        let contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 10
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(titleLabel)
        root.addSubview(explanationLabel)
        root.addSubview(contentStack)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        explanationLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            explanationLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            explanationLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            explanationLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            contentStack.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: explanationLabel.bottomAnchor, constant: 18),
        ])

        exampleImageViews.removeAll(keepingCapacity: true)
        exampleRows.removeAll(keepingCapacity: true)
        resolutionErrors.removeAll(keepingCapacity: true)
        focusOrder = [titleLabel, explanationLabel]

        for example in Self.examples {
            let catalogEntry = assetCatalog.entries.first { $0.id == example.assetIdentifier }
            let accessibleName = catalogEntry?.accessibleName.isEmpty == false
                ? catalogEntry!.accessibleName
                : example.accessibleName
            let accessibleDescription = catalogEntry?.accessibleDescription.isEmpty == false
                ? catalogEntry!.accessibleDescription
                : example.accessibleDescription
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .top
            row.spacing = 10

            let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: 48, height: 48))
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.setAccessibilityElement(catalogEntry?.isDecorative != true)
            imageView.setAccessibilityLabel(accessibleName)
            imageView.setAccessibilityHelp(accessibleDescription)
            imageView.setAccessibilityRole(.image)
            imageView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: 48),
                imageView.heightAnchor.constraint(equalToConstant: 48),
            ])
            do {
                imageView.image = try assetCatalog.image(
                    for: example.assetIdentifier,
                    variant: variant
                )
            } catch {
                resolutionErrors.append(error)
            }

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
            button.topAnchor.constraint(equalTo: contentStack.bottomAnchor, constant: 18),
            button.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
        ])
        doneButton = button
        focusOrder.append(button)

        root.setAccessibilityChildren(focusOrder)
        view = root
    }

    @objc private func done(_: Any?) {
        onDismiss()
    }
}
