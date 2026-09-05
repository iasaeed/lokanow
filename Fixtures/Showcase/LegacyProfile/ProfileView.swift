import UIKit
final class LocalizationBundleToken: NSObject {}
public final class ProfileView: UIView {
    public func configure() {
        let label = UILabel()
        label.text = "Your profile"
        let button = UIButton(type: .system)
        button.setTitle("Save changes", for: .normal)
        accessibilityLabel = "Profile editor"
    }
}
