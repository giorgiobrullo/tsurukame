// Copyright 2026 David Sansome
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import PromiseKit
import SwiftUI
import UIKit
import WaniKaniAPI

private let kPrivacyPolicyURL = "https://github.com/davidsansome/tsurukame/wiki/Privacy-Policy"

// SwiftUI rewrite of LoginViewController. Keeps both auth paths (API token and the email/password
// web login) and the LoginViewControllerDelegate contract that AppDelegate relies on.

@available(iOS 15.0, *)
final class LoginModel: ObservableObject {
  enum Method: Hashable { case apiToken, emailPassword }

  @Published var method: Method = .apiToken
  @Published var apiToken = ""
  @Published var email = ""
  @Published var password = ""
  @Published var isBusy = false
  @Published var errorMessage: String?

  weak var delegate: LoginViewControllerDelegate?
  var forcedEmail: String? {
    didSet {
      if let forcedEmail = forcedEmail {
        email = forcedEmail
        method = .emailPassword
      }
    }
  }

  var canSubmit: Bool {
    switch method {
    case .apiToken:
      return !apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case .emailPassword:
      return !email.isEmpty && !password.isEmpty
    }
  }

  func submit() {
    guard canSubmit, !isBusy else { return }
    isBusy = true
    errorMessage = nil

    switch method {
    case .apiToken:
      let token = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
      WaniKaniAPIClient(apiToken: token).user(progress: Progress()).done { user in
        NSLog("Login success! User is at level: \(user.currentLevel)")
        Settings.userApiToken = token
        Settings.userEmailAddress = ""
        self.succeed()
      }.catch { err in
        if let wkError = err as? WaniKaniAPIError,
           wkError.message?.contains("hibernating") ?? false {
          self.fail(Self.hibernatingMessage)
        } else {
          self.fail("Unable to log in with that API token. (\(err.localizedDescription))")
        }
      }

    case .emailPassword:
      WaniKaniWebClient().login(email: email, password: password).done { result in
        NSLog("Login success!")
        Settings.userApiToken = result.apiToken
        Settings.userEmailAddress = self.email
        self.succeed()
      }.catch { error in
        if let wkError = error as? WaniKaniAPI.WaniKaniWebClientError,
           wkError == .accountHibernating {
          self.fail(Self.hibernatingMessage)
        } else {
          self.fail(error.localizedDescription)
        }
      }
    }
  }

  func pasteToken() {
    if let text = UIPasteboard.general.string {
      apiToken = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }

  private func succeed() {
    isBusy = false
    delegate?.loginComplete()
  }

  private func fail(_ message: String) {
    DispatchQueue.main.async {
      self.isBusy = false
      self.errorMessage = message
    }
  }

  private static let hibernatingMessage =
    "This account is hibernating. Log in on wanikani.com to reactivate it, then try again."
}

@available(iOS 15.0, *)
struct LoginView: View {
  @ObservedObject var model: LoginModel
  @FocusState private var focused: Field?

  private enum Field { case email, password, token }

  var body: some View {
    ZStack {
      LinearGradient(colors: [Color(uiColor: TKMStyle.radicalColor1),
                              Color(uiColor: TKMStyle.radicalColor2)],
                     startPoint: .top, endPoint: .bottom)
        .ignoresSafeArea()

      ScrollView {
        VStack(spacing: 24) {
          header
          card
          privacyPolicy
        }
        .padding(20)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
      }

      if model.isBusy {
        Color.black.opacity(0.25).ignoresSafeArea()
        ProgressView()
          .controlSize(.large)
          .padding(24)
          .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
      }
    }
    .tint(Color(uiColor: TKMStyle.radicalColor2))
    .alert("Couldn't log in", isPresented: Binding(get: { model.errorMessage != nil },
                                                   set: { if !$0 { model.errorMessage = nil } })) {
      Button("OK", role: .cancel) { model.errorMessage = nil }
    } message: {
      Text(model.errorMessage ?? "")
    }
  }

  private var header: some View {
    VStack(spacing: 8) {
      Image(systemName: "tortoise.fill")
        .font(.system(size: 52))
        .foregroundStyle(.white)
      Text("Tsurukame")
        .font(.system(size: 34, weight: .bold, design: .rounded))
        .foregroundStyle(.white)
      Text("Sign in to your WaniKani account")
        .font(.subheadline)
        .foregroundStyle(.white.opacity(0.9))
    }
    .padding(.top, 32)
  }

  private var card: some View {
    VStack(spacing: 16) {
      Picker("Login method", selection: $model.method) {
        Text("API token").tag(LoginModel.Method.apiToken)
        Text("Email & password").tag(LoginModel.Method.emailPassword)
      }
      .pickerStyle(.segmented)

      if model.method == .apiToken {
        tokenFields
      } else {
        emailPasswordFields
      }

      Button(action: { model.submit() }) {
        Text("Sign in")
          .font(.headline)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
      }
      .buttonStyle(.borderedProminent)
      .disabled(!model.canSubmit || model.isBusy)
    }
    .padding(18)
    .background(Color(uiColor: .secondarySystemGroupedBackground))
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
  }

  private var tokenFields: some View {
    VStack(spacing: 10) {
      HStack {
        SecureField("API token", text: $model.apiToken)
          .textContentType(.password)
          .autocorrectionDisabled()
          .textInputAutocapitalization(.never)
          .focused($focused, equals: .token)
          .submitLabel(.go)
          .onSubmit { model.submit() }
        Button("Paste") { model.pasteToken() }
          .font(.subheadline.weight(.semibold))
      }
      Text("Find your token at wanikani.com under Settings → API Tokens.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var emailPasswordFields: some View {
    VStack(spacing: 10) {
      TextField("Email", text: $model.email)
        .textContentType(.username)
        .keyboardType(.emailAddress)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .disabled(model.forcedEmail != nil)
        .focused($focused, equals: .email)
        .submitLabel(.next)
        .onSubmit { focused = .password }
      SecureField("Password", text: $model.password)
        .textContentType(.password)
        .focused($focused, equals: .password)
        .submitLabel(.go)
        .onSubmit { model.submit() }
    }
  }

  private var privacyPolicy: some View {
    Button("Privacy policy") {
      if let url = URL(string: kPrivacyPolicyURL) {
        UIApplication.shared.open(url)
      }
    }
    .font(.footnote)
    .foregroundStyle(.white)
  }
}

/// Hosts `LoginView` and exposes the same `delegate` / `forcedEmail` surface as the old
/// `LoginViewController`, so `AppDelegate` can swap one for the other.
@available(iOS 15.0, *)
final class LoginHostingController: UIHostingController<LoginView>, TKMViewController {
  let model: LoginModel

  var canSwipeToGoBack: Bool { false }

  weak var delegate: LoginViewControllerDelegate? {
    didSet { model.delegate = delegate }
  }

  var forcedEmail: String? {
    didSet { model.forcedEmail = forcedEmail }
  }

  init() {
    let model = LoginModel()
    self.model = model
    super.init(rootView: LoginView(model: model))
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.isNavigationBarHidden = true
  }
}
