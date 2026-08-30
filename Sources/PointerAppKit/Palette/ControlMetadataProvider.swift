import AppKit

@MainActor
public struct ControlMetadata: Equatable, Sendable {
    public let identifier: String
    public let accessibleName: String
    public let help: String?
    public let value: String?
    public let role: String
    public let isEnabled: Bool
    public let isKeyboardReachable: Bool
}

@MainActor
public protocol ControlMetadataProviding: AnyObject {
    func metadata() -> [ControlMetadata]
}

@MainActor
public final class ControlMetadataInventory: ControlMetadataProviding {
    private weak var palette: PalettePanel?
    private weak var menuBar: MenuBarController?

    public init(palette: PalettePanel, menuBar: MenuBarController?) {
        self.palette = palette
        self.menuBar = menuBar
    }

    public func metadata() -> [ControlMetadata] {
        var rows: [ControlMetadata] = []
        if let palette {
            palette.paletteViewController.loadViewIfNeeded()
            let overflowMenu = palette.paletteViewController.controls
                .first { $0.identifier?.rawValue == "palette.tools.overflow" }
                .flatMap { ($0 as? NSPopUpButton)?.menu }
            let overflowToolIDs = Set(
                overflowMenu?.items
                    .compactMap { $0.identifier?.rawValue }
                    .filter { $0.hasPrefix("palette.overflow.tool.") }
                    ?? []
            )
            for control in palette.paletteViewController.controls {
                guard let rawIdentifier = control.identifier?.rawValue,
                      !(control.isHidden && rawIdentifier.hasPrefix("palette.tool.")
                          && overflowToolIDs.contains(
                              "palette.overflow.tool."
                                  + rawIdentifier.dropFirst("palette.tool.".count)
                          ))
                else {
                    continue
                }
                rows.append(metadata(for: control))
                guard control.identifier?.rawValue == "palette.tools.overflow",
                      let overflow = control as? NSPopUpButton,
                      let menu = overflow.menu else { continue }
                append(menu.items, to: &rows)
            }
        }
        if let menuBar {
            if let button = menuBar.statusItem?.button {
                rows.append(metadata(for: button))
            }
            if let menu = menuBar.menu {
                append(menu.items, to: &rows)
            }
        }
        return rows
    }

    private func metadata(for control: NSControl) -> ControlMetadata {
        let rawIdentifier = control.identifier?.rawValue
        let identifier = rawIdentifier.flatMap { $0.isEmpty ? nil : $0 }
            ?? "palette.control.unknown"
        let accessibleName = control.accessibilityLabel() ?? title(of: control)
        return ControlMetadata(
            identifier: identifier,
            accessibleName: accessibleName,
            help: nonEmpty(control.accessibilityHelp()),
            value: stringValue(control.accessibilityValue()),
            role: role(of: control),
            isEnabled: control.isEnabled,
            isKeyboardReachable: control.isEnabled
                && !control.isHidden
                && control.acceptsFirstResponder
                && rawIdentifier?.isEmpty == false
                && identifier != "palette.status"
        )
    }

    private func append(_ items: [NSMenuItem], to rows: inout [ControlMetadata]) {
        for item in items where !item.isSeparatorItem {
            rows.append(metadata(for: item))
            if let submenu = item.submenu {
                append(submenu.items, to: &rows)
            }
        }
    }

    private func metadata(for item: NSMenuItem) -> ControlMetadata {
        let rawIdentifier = item.identifier?.rawValue
        return ControlMetadata(
            identifier: rawIdentifier.flatMap { $0.isEmpty ? nil : $0 }
                ?? "menu.item.\(item.title)",
            accessibleName: item.accessibilityLabel() ?? item.title,
            help: nonEmpty(item.accessibilityHelp()),
            value: stringValue(item.accessibilityValue()),
            role: role(of: item),
            isEnabled: item.isEnabled,
            isKeyboardReachable: item.isEnabled
                && !item.isHidden
                && rawIdentifier?.isEmpty == false
        )
    }

    private func role(of control: NSControl) -> String {
        if let role = control.accessibilityRole()?.rawValue {
            return role
        }
        switch control {
        case is NSPopUpButton:
            return "AXPopUpButton"
        case is NSButton:
            return "AXButton"
        case is NSColorWell:
            return "AXColorWell"
        case is NSSlider:
            return "AXSlider"
        case is NSTextField:
            return "AXStaticText"
        default:
            return "AXUnknown"
        }
    }

    private func role(of item: NSMenuItem) -> String {
        item.accessibilityRole()?.rawValue ?? "AXMenuItem"
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private func title(of control: NSControl) -> String {
        switch control {
        case let button as NSButton:
            return button.title
        case let popup as NSPopUpButton:
            return popup.title
        case let field as NSTextField:
            return field.stringValue
        case let slider as NSSlider:
            return slider.accessibilityLabel() ?? "Slider"
        default:
            return control.accessibilityLabel() ?? "Control"
        }
    }

    private func stringValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return String(describing: value)
    }
}
