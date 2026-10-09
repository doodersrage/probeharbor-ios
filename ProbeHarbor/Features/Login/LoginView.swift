import SwiftUI

enum LoginMode { case signIn, register, forgotPassword }

struct LoginView: View {
    @Environment(AppModel.self) private var app
    @State private var mode: LoginMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var loading = false
    @State private var error: String?
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Wordmark(size: 30)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textMuted)
                }
                .padding(.top, 40)

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if mode != .forgotPassword {
                        SecureField("Password", text: $password)
                            .textContentType(mode == .register ? .newPassword : .password)
                    }
                }
                .textFieldStyle(.roundedBorder)

                StatusBanner(message: message, error: error)

                Button(action: submit) {
                    if loading { ProgressView().tint(Theme.accentInk) } else { Text(submitTitle) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(loading)

                if mode == .signIn {
                    VStack(spacing: 10) {
                        Text("or continue with")
                            .font(.footnote)
                            .foregroundStyle(Theme.textMuted)
                            .frame(maxWidth: .infinity)
                        ForEach(["google", "github", "discord"], id: \.self) { provider in
                            Button {
                                signInWith(provider)
                            } label: {
                                Text(provider.capitalized == "Github" ? "GitHub" : provider.capitalized)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(loading)
                        }
                    }
                }

                HStack {
                    switch mode {
                    case .signIn:
                        Button("Create account") { switchMode(.register) }
                        Spacer()
                        Button("Forgot password?") { switchMode(.forgotPassword) }
                    case .register, .forgotPassword:
                        Button("Back to sign in") { switchMode(.signIn) }
                    }
                }
                .font(.footnote)
            }
            .padding(20)
        }
        .screenBackground()
    }

    private var subtitle: String {
        switch mode {
        case .signIn: return "Sign in to probeharbor.dev"
        case .register: return "Create your ProbeHarbor account"
        case .forgotPassword: return "We'll email you a reset link"
        }
    }

    private var submitTitle: String {
        switch mode {
        case .signIn: return "Sign in"
        case .register: return "Create account"
        case .forgotPassword: return "Send reset email"
        }
    }

    private func switchMode(_ next: LoginMode) {
        mode = next
        error = nil
        message = nil
    }

    private func submit() {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        switch mode {
        case .signIn:
            guard !trimmed.isEmpty, !password.isEmpty else { error = "Email and password are required"; return }
        case .register:
            guard !trimmed.isEmpty, !password.isEmpty else { error = "Email and password are required"; return }
            guard password.count >= 8 else { error = "Password must be at least 8 characters"; return }
        case .forgotPassword:
            guard trimmed.contains("@") else { error = "Enter your account email"; return }
        }
        run {
            switch mode {
            case .signIn:
                app.didSignIn(try await app.auth.signIn(email: trimmed, password: password))
            case .register:
                if try await app.auth.signUp(email: trimmed, password: password) {
                    app.didSignIn(AuthOutcome(needsMfa: false))
                } else {
                    mode = .signIn
                    message = "Account created. Check your email if confirmation is required."
                }
            case .forgotPassword:
                try await app.auth.resetPassword(email: trimmed)
                mode = .signIn
                message = "Password reset email sent if an account exists."
            }
        }
    }

    private func signInWith(_ provider: String) {
        run { app.didSignIn(try await app.auth.signInWithOAuth(provider: provider)) }
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        loading = true
        error = nil
        message = nil
        Task {
            do {
                try await work()
            } catch is CancellationError {
                // User closed the sign-in sheet.
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }
}

struct MFAView: View {
    @Environment(AppModel.self) private var app
    @State private var code = ""
    @State private var yubikeyOTP = ""
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Wordmark(size: 26).padding(.top, 40)
                Text("Two-step verification").font(.title3.weight(.semibold))
                Text("Enter the 6-digit code from your authenticator app, or tap your YubiKey in the OTP field.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textMuted)

                TextField("6-digit code", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .onChange(of: code) { _, value in
                        let digits = String(value.filter(\.isNumber).prefix(6))
                        if digits != value { code = digits }
                    }
                TextField("YubiKey OTP (optional)", text: $yubikeyOTP)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                StatusBanner(error: error)

                Button(action: verify) {
                    if loading { ProgressView().tint(Theme.accentInk) } else { Text("Verify") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(loading)

                Button("Use a different account", role: .cancel) {
                    Task { await app.signOut() }
                }
                .font(.footnote)
            }
            .textFieldStyle(.roundedBorder)
            .padding(20)
        }
        .screenBackground()
    }

    private func verify() {
        let otp = yubikeyOTP.trimmingCharacters(in: .whitespaces)
        if !otp.isEmpty {
            guard otp.count >= 44 else { error = "Tap your YubiKey to fill the OTP field"; return }
        } else if code.count != 6 {
            error = "Enter the 6-digit code or a YubiKey OTP"
            return
        }
        loading = true
        error = nil
        Task {
            do {
                try await app.auth.verifyMfa(code: code, yubikeyOTP: otp.isEmpty ? nil : otp)
                app.didVerifyMfa()
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }
}
