import Foundation
import CoreText

enum FontLoader {
    static func registerAll() {
        let names = ["Sora", "Manrope"]
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                NSLog("FontLoader: \(name).ttf not found in bundle")
                continue
            }
            var err: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &err) {
                if let e = err?.takeRetainedValue() {
                    let code = CFErrorGetCode(e)
                    if code == CTFontManagerError.alreadyRegistered.rawValue { continue }
                    NSLog("FontLoader: failed \(name): \(e)")
                }
            }
        }
    }
}
