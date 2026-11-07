import Testing
import CoreDomain
@testable import ShopDomain

@Suite("Магазин (задел)")
struct ShopTests {
    @Test func orderTotal() {
        let order = Order(id: ID(), customerId: UserID(), items: [
            OrderItem(productId: ID(), quantity: 1, unitPrice: .rubles(45_000)),
            OrderItem(productId: ID(), quantity: 3, unitPrice: .rubles(350)),
        ], pickupClubId: ClubID())
        #expect(order.total == .rubles(46_050))
    }
}
