// IdentityKit/Sources/IdentityDomain/Identity.swift
import Foundation
import CoreDomain

public enum OTPChannel: String, Codable, Sendable { case sms = "SMS", email = "EMAIL" }

public struct OTPChallenge: Hashable, Codable, Sendable {
    public let otpSessionId: UUID
    public let expiresIn: Int
    public let resendAvailableIn: Int
    public let codeLength: Int
}

public struct TokenPair: Hashable, Codable, Sendable {
    public let accessToken: String
    public let accessTokenExpiresIn: Int
    public let refreshToken: String
    public let refreshTokenExpiresIn: Int
}

/// Хранилище токенов. Реализация — Keychain с `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (NFR-003.4).
public protocol TokenStore: Sendable {
    func load() async -> TokenPair?
    func save(_ tokens: TokenPair) async throws
    func clear() async
}

public protocol AuthRepository: Sendable {
    func requestCode(channel: OTPChannel, destination: String, role: UserRole?, firstName: String?) async throws -> OTPChallenge
    func verify(otpSessionId: UUID, code: String) async throws -> (tokens: TokenPair, userId: UserID, isNew: Bool)
    /// Ротация refresh-токена; повторное использование старого → 401 TOKEN_REUSED и выход.
    func refresh(_ refreshToken: String) async throws -> TokenPair
}
