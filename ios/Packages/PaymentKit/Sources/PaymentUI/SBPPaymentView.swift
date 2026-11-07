// PaymentKit/Sources/PaymentUI/SBPPaymentView.swift — ЗАДЕЛ: свёрстан, в проде не показывается
import SwiftUI
import CoreImage.CIFilterBuiltins
import CoreDomain
import DesignSystem

@MainActor
@Observable
public final class SBPPaymentViewModel {
    public enum Phase: Equatable { case waiting, succeeded, failed, expired }

    public private(set) var phase: Phase = .waiting
    public let session: PaymentSession
    private let gateway: PaymentGateway

    public init(session: PaymentSession, gateway: PaymentGateway) {
        self.session = session
        self.gateway = gateway
    }

    /// Источник истины — сервер (webhook банка). Возврат из банка по universal link лишь будит этот поток.
    public func observe() async {
        do {
            for try await status in gateway.statusUpdates(of: session.paymentId) {
                switch status {
                case .succeeded: phase = .succeeded; return
                case .failed: phase = .failed; return
                case .expired: phase = .expired; return
                default: continue
                }
            }
        } catch {
            // Сетевые ошибки не меняют статус: экран остаётся в ожидании, поток переподключится.
        }
    }
}

public struct SBPPaymentView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.palette) private var palette
    @State private var viewModel: SBPPaymentViewModel

    public init(viewModel: SBPPaymentViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: Space.l) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, viewModel.session.expiresAt.timeIntervalSince(context.date))
                Text("Оплатите до \(viewModel.session.expiresAt.formatted(.dateTime.hour().minute())) · осталось \(Duration.seconds(remaining).formatted(.time(pattern: .minuteSecond)))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(palette.textSecondary)
            }
            #if canImport(UIKit)
            if let qr = Self.qrImage(from: viewModel.session.qrPayload) {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 200, height: 200)
                    .padding(Space.m)
                    .background(.white, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
                    .accessibilityLabel("QR-код для оплаты через СБП с другого устройства")
            }
            #endif
            Button("Оплатить через СБП") { openURL(viewModel.session.paymentURL) }
                .buttonStyle(.cueGlassProminent)
            switch viewModel.phase {
            case .waiting: ProgressView("Ждём подтверждение банка…")
            case .succeeded: Label("Оплачено, тренировка подтверждена", systemImage: "checkmark.seal.fill")
            case .failed: Label("Оплата не прошла", systemImage: "xmark.octagon")
            case .expired: Label("Время оплаты истекло, слот освобождён", systemImage: "clock.badge.xmark")
            }
        }
        .padding(Space.l)
        .glassCard()
        .task { await viewModel.observe() }
    }

    #if canImport(UIKit)
    static func qrImage(from payload: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
    #endif
}
