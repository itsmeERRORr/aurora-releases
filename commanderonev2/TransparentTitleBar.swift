#if os(macOS)
import AppKit
import SwiftUI

/// Cor de fundo da barra de título (igual ao topo do gradiente da app) para manter o aspeto quando a janela está inativa.
private let titleBarBackgroundColor = NSColor(red: 0x4A/255.0, green: 0x56/255.0, blue: 0x80/255.0, alpha: 1)

/// Configura a janela para barra de título transparente, deixando o fundo da app aparecer atrás dos botões de janela.
struct TransparentTitleBar: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        TransparentTitleBarHostView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? TransparentTitleBarHostView)?.configureWindow()
    }
}

fileprivate final class TransparentTitleBarHostView: NSView {
    private var keyStateObservers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            for o in keyStateObservers { NotificationCenter.default.removeObserver(o) }
            keyStateObservers = []
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.configureWindow()
        }
    }

    func configureWindow() {
        guard let window = window else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.backgroundColor = window.isKeyWindow ? .clear : titleBarBackgroundColor

        if keyStateObservers.isEmpty {
            keyStateObservers = [
                NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                    self?.updateTitleBarForKeyState(isKey: false)
                },
                NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                    self?.updateTitleBarForKeyState(isKey: true)
                }
            ]
        }
    }

    private func updateTitleBarForKeyState(isKey: Bool) {
        guard let window = window else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = isKey ? .clear : titleBarBackgroundColor
        window.contentView?.needsDisplay = true
    }
}
#endif
