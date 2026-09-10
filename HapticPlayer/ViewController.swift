import UIKit
import SwiftUI

class ViewController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Launch the liquid glass SwiftUI view directly
        let swiftUIView = HapticClipGridView()
        let host = UIHostingController(rootView: swiftUIView)
        host.modalPresentationStyle = .fullScreen
        present(host, animated: true)
    }
}
