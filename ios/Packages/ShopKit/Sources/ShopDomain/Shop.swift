// ShopKit/Sources/ShopDomain/Shop.swift — ЗАДЕЛ (v1.0, FR-022)
import Foundation
import CoreDomain

public enum ProductCategory: String, Codable, Sendable, CaseIterable {
    case cue = "CUE", shaft = "SHAFT", caseBag = "CASE", glove = "GLOVE", chalk = "CHALK", tip = "TIP"
}

public struct Product: Identifiable, Hashable, Codable, Sendable {
    public let id: ID<Product>
    public let sku: String
    public var title: String
    public var brand: String
    public var category: ProductCategory
    public var specs: [String: String]      // вес, длина, наклейка, материал
    public var price: Money
    public var imageURLs: [URL]

    public init(id: ID<Product>, sku: String, title: String, brand: String, category: ProductCategory,
                specs: [String: String] = [:], price: Money, imageURLs: [URL] = []) {
        self.id = id
        self.sku = sku
        self.title = title
        self.brand = brand
        self.category = category
        self.specs = specs
        self.price = price
        self.imageURLs = imageURLs
    }
}

public struct OrderItem: Hashable, Codable, Sendable {
    public let productId: ID<Product>
    public let quantity: Int
    public let unitPrice: Money

    public init(productId: ID<Product>, quantity: Int, unitPrice: Money) {
        precondition(quantity > 0)
        self.productId = productId
        self.quantity = quantity
        self.unitPrice = unitPrice
    }
}

public enum OrderStatus: String, Codable, Sendable {
    case created = "CREATED", awaitingPayment = "AWAITING_PAYMENT", paid = "PAID"
    case readyForPickup = "READY_FOR_PICKUP", completed = "COMPLETED", cancelled = "CANCELLED"
}

/// Заказ оплачивается через тот же порт `PaymentGateway`, что и тренировки.
public struct Order: Identifiable, Hashable, Codable, Sendable {
    public let id: ID<Order>
    public let customerId: UserID
    public let items: [OrderItem]
    public let pickupClubId: ClubID
    public private(set) var status: OrderStatus
    public private(set) var paymentId: PaymentID?

    public init(id: ID<Order>, customerId: UserID, items: [OrderItem], pickupClubId: ClubID) {
        self.id = id
        self.customerId = customerId
        self.items = items
        self.pickupClubId = pickupClubId
        self.status = .created
    }

    public var total: Money {
        Money(amountMinor: items.reduce(0) { $0 + $1.unitPrice.amountMinor * Int64($1.quantity) })
    }

    public mutating func awaitPayment(_ paymentId: PaymentID) {
        guard status == .created else { return }
        self.paymentId = paymentId
        status = .awaitingPayment
    }

    public mutating func markPaid() {
        guard status == .awaitingPayment else { return }
        status = .paid
    }
}
