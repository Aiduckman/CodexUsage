import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let viewModel: UsageViewModel
    private var cancellables: Set<AnyCancellable> = []

    init(viewModel: UsageViewModel) {
        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 286, height: 360)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarContentView(viewModel: viewModel)
        )
        popover.delegate = self

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.imagePosition = .imageLeft
        }

        viewModel.$usage
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)

        viewModel.$lastError
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)

        updateStatusItem()
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }

        button.image = Self.openAIMarkImage()
        button.image?.isTemplate = false
        button.attributedTitle = NSAttributedString(
            string: " \(viewModel.menuBarLabel)",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
                .foregroundColor: viewModel.menuBarNSColor
            ]
        )
        button.toolTip = "CodexUsage"
    }

    private static func openAIMarkImage() -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor(red: 0.06, green: 0.64, blue: 0.50, alpha: 1).setStroke()
        for index in 0..<6 {
            let transform = NSAffineTransform()
            transform.translateX(by: size.width / 2, yBy: size.height / 2)
            transform.rotate(byDegrees: CGFloat(index) * 60)
            transform.translateX(by: -size.width / 2, yBy: -size.height / 2)
            transform.concat()

            let rect = NSRect(x: 8.2, y: 5.3, width: 7.8, height: 4.8)
            let path = NSBezierPath(roundedRect: rect, xRadius: 2.4, yRadius: 2.4)
            path.lineWidth = 1.45
            path.stroke()

            transform.invert()
            transform.concat()
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
