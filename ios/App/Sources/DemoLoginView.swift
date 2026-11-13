// App/Sources/DemoLoginView.swift — демо-вход для тестирования без backend.
// Повторяет поток FR-001 (телефон → код из SMS), но проверяет учётки локально.
// Когда появится Identity Service, экран заменяется реальным входом через IdentityKit.
import SwiftUI
import CoreDomain
import DesignSystem

/// Тестовые учётки. Код подтверждения для всех — 1234.
enum DemoAccount: String, CaseIterable, Identifiable {
    case coach
    case veronica
    case student
    case natasha
    case dmitry

    var id: Self { self }

    var displayName: String {
        switch self {
        case .coach: "Алексей Воронов"
        case .veronica: "Вероника Смирнова"
        case .student: "Иван Петров"
        case .natasha: "Наталья Белова"
        case .dmitry: "Дмитрий Орлов (Про)"
        }
    }

    var phone: String {
        switch self {
        case .coach: "+7 900 000-00-01"
        case .veronica: "+7 900 000-00-03"
        case .student: "+7 900 000-00-02"
        case .natasha: "+7 900 000-00-04"
        case .dmitry: "+7 900 000-00-05"
        }
    }

    var isStudent: Bool { self == .student || self == .natasha || self == .dmitry }

    var role: UserRole { isStudent ? .student : .trainer }

    var roleTitle: String { isStudent ? "Ученик" : "Тренер" }

    /// ID пользователя в демо-данных.
    var userId: UserID {
        switch self {
        case .coach: DemoBackend.alexeyId
        case .veronica: DemoBackend.veronikaId
        case .student: DemoBackend.ivanId
        case .natasha: DemoBackend.natashaId
        case .dmitry: DemoBackend.dmitryId
        }
    }

    static let otpCode = "1234"

    /// Поиск по номеру в любом формате: 8 900…, +7 900…, 900…
    static func find(phone: String) -> DemoAccount? {
        guard let entered = try? PhoneNumber(phone) else { return nil }
        return allCases.first { (try? PhoneNumber($0.phone))?.e164 == entered.e164 }
    }
}

struct DemoLoginView: View {
    enum Step { case phone, code }

    @Environment(\.palette) private var palette
    let container: AppContainer
    @State private var step: Step = .phone
    @State private var phone = ""
    @State private var code = ""
    @State private var account: DemoAccount?
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: Space.l) {
                VStack(spacing: Space.s) {
                    Image(systemName: "circle.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(palette.accent)
                    Text("Биток")
                        .font(.largeTitle.weight(.semibold))
                        .fontDesign(palette.headingDesign)
                    Text("Каждая тренировка начинается с битка")
                        .font(.callout)
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(.top, 48)

                VStack(alignment: .leading, spacing: Space.m) {
                    switch step {
                    case .phone:
                        Text("Номер телефона").font(.headline)
                        TextField("+7 900 000-00-02", text: $phone)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .focused($focused)
                            .onChange(of: phone) { old, value in
                                // Стирание дефиса/пробела стирает и цифру перед ним
                                var source = value
                                if value.count < old.count, value.filter(\.isNumber) == old.filter(\.isNumber) {
                                    source = String(source.filter(\.isNumber).dropLast())
                                }
                                let masked = Fmt.phoneMask(source)
                                if masked != value { phone = masked }
                            }
                            .padding(Space.m)
                            .glassCard(cornerRadius: Radius.m)
                        Button("Получить код") { requestCode() }
                            .buttonStyle(.cueGlassProminent)
                            .disabled(phone.filter(\.isNumber).count < 10)
                    case .code:
                        Text("Код из SMS отправлен на \(account?.phone ?? phone)").font(.headline)
                        TextField("Код", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .focused($focused)
                            .onChange(of: code) { _, value in
                                let digits = String(value.filter(\.isNumber).prefix(4))
                                if digits != value { code = digits }
                                if digits.count == 4 { verify() }
                            }
                            .padding(Space.m)
                            .glassCard(cornerRadius: Radius.m)
                        Text("Демо-режим: код для тестовых учёток — \(DemoAccount.otpCode)")
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                        Button("Войти") { verify() }
                            .buttonStyle(.cueGlassProminent)
                            .disabled(code.count < 4)
                        Button("Изменить номер") {
                            step = .phone
                            code = ""
                            error = nil
                        }
                        .frame(maxWidth: .infinity)
                    }
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(palette.statusCancelled)
                    }
                }
                .padding(Space.l)
                .glassCard()

                VStack(alignment: .leading, spacing: Space.s) {
                    Text("Тестовые учётки").font(.headline)
                    ForEach(DemoAccount.allCases) { demo in
                        Button { focused = false; hideKeyboard(); container.signIn(demo) } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("\(demo.roleTitle): \(demo.displayName)").font(.callout.weight(.semibold))
                                    Text("\(demo.phone) · код \(DemoAccount.otpCode)")
                                        .font(.caption)
                                        .foregroundStyle(palette.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.right.circle.fill").foregroundStyle(palette.accent)
                            }
                            .padding(Space.m)
                            .glassCard(cornerRadius: Radius.m)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(Space.l)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(ThemedBackground())
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Готово") { focused = false }
            }
        }
    }

    private func requestCode() {
        guard let found = DemoAccount.find(phone: phone) else {
            error = "Такой учётки нет. Используйте тестовые номера ниже."
            return
        }
        account = found
        error = nil
        step = .code
        focused = true
    }

    private func verify() {
        guard let account, code == DemoAccount.otpCode else {
            error = "Неверный код"
            return
        }
        focused = false
        hideKeyboard()
        container.signIn(account)
    }
}
