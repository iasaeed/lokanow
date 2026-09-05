import XCTest
@testable import Checkout
final class CheckoutTests: XCTestCase {
    func testEnglishResourceBundle() { XCTAssertEqual(CheckoutLocalization.value("checkout.existing", locale: "en"), "Existing") }
    func testEnglishFallback() { XCTAssertEqual(CheckoutLocalization.value("missing", locale: "en"), "English fallback") }
}
