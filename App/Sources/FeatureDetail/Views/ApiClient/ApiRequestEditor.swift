import ADBKit
import AppKit
import SwiftUI

struct ApiRequestEditor: View {
    @Bindable var model: ApiClientModel
    @Binding var tab: ApiRequestTab
    let compact: Bool

    @State private var codeTarget: CodeTarget = .curl

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                tabPicker(.segmented)
                tabPicker(.menu)
            }
            Divider()
            content
        }
        .background(.bgSurface.opacity(0.5))
    }

    private func tabPicker(_ style: some PickerStyle) -> some View {
        Picker("", selection: $tab) {
            ForEach(ApiRequestTab.allCases) { value in
                Text(label(for: value)).tag(value)
            }
        }
        .labelsHidden()
        .pickerStyle(style)
        .padding(8)
    }

    private func label(for tab: ApiRequestTab) -> String {
        switch tab {
        case .params:
            let count = model.current.queryParams.count + model.current.pathVariables.count
            return count > 0 ? "Params (\(count))" : "Params"
        case .headers:
            let count = model.current.headers.count
            return count > 0 ? "Headers (\(count))" : "Headers"
        case .body:
            return model.current.body.type == .none ? "Body" : "Body •"
        case .auth:
            return model.current.auth.type == .none ? "Auth" : "Auth •"
        case .tests:
            let count = model.current.assertions.count
            return count > 0 ? "Tests (\(count))" : "Tests"
        case .settings:
            return "Settings"
        case .code:
            return "Code"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .params: paramsTab
        case .headers: headersTab
        case .body: bodyTab
        case .auth: authTab
        case .tests: testsTab
        case .settings: settingsTab
        case .code: codeTab
        }
    }

    // MARK: - Params

    private var paramsTab: some View {
        VStack(spacing: 0) {
            ApiKeyValueEditor(
                title: "Query Parameters",
                placeholder: "No parameters. Anything after ? in the URL shows up here.",
                items: $model.current.queryParams
            )
            if !pathVariableNames.isEmpty {
                Divider()
                pathVariables
            }
        }
    }

    /// `:name` placeholders present in the URL path.
    private var pathVariableNames: [String] {
        let base = model.current.url.components(separatedBy: "?").first ?? ""
        guard let schemeEnd = base.range(of: "://") else { return [] }
        let afterScheme = base[schemeEnd.upperBound...]
        guard let firstSlash = afterScheme.firstIndex(of: "/") else { return [] }
        return base[firstSlash...]
            .components(separatedBy: "/")
            .filter { $0.hasPrefix(":") && $0.count > 1 }
            .map { String($0.dropFirst()) }
    }

    private var pathVariables: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Path Variables").font(.app(.headline))
                .padding(.horizontal, 12)
                .padding(.top, 8)
            ForEach(pathVariableNames, id: \.self) { name in
                HStack {
                    Text(":\(name)")
                        .font(.app(.caption, design: .monospaced))
                        .frame(width: 110, alignment: .leading)
                    TextField("Value", text: pathBinding(name))
                        .textFieldStyle(.roundedBorder)
                        .font(.app(.caption, design: .monospaced))
                }
                .padding(.horizontal, 12)
            }
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pathBinding(_ name: String) -> Binding<String> {
        Binding(
            get: { model.current.pathVariables.first { $0.key == name }?.value ?? "" },
            set: { newValue in
                if let index = model.current.pathVariables.firstIndex(where: { $0.key == name }) {
                    model.current.pathVariables[index].value = newValue
                } else {
                    model.current.pathVariables.append(ApiKeyValue(key: name, value: newValue))
                }
            }
        )
    }

    // MARK: - Headers

    private var headersTab: some View {
        ApiKeyValueEditor(
            title: "Headers",
            placeholder: "No headers yet. Click + to add one.",
            items: $model.current.headers
        )
    }

    // MARK: - Body

    private var bodyTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                bodyPicker(.segmented)
                bodyPicker(.menu)
            }
            bodyContent
        }
    }

    private func bodyPicker(_ style: some PickerStyle) -> some View {
        Picker("", selection: $model.current.body.type) {
            ForEach(BodyType.allCases, id: \.self) { type in
                Text(ApiLabels.body(type)).tag(type)
            }
        }
        .labelsHidden()
        .pickerStyle(style)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch model.current.body.type {
        case .none:
            hint("This request has no body.")
        case .json:
            jsonEditor
        case .raw:
            rawEditor
        case .formUrlEncoded:
            ApiKeyValueEditor(
                title: "Form Fields",
                placeholder: "No fields yet. Sent as application/x-www-form-urlencoded.",
                items: $model.current.body.formFields
            )
        case .multipart:
            ApiMultipartEditor(fields: $model.current.body.multipartFields)
        case .graphql:
            graphqlEditor
        case .binary:
            binaryEditor
        }
    }

    private var jsonEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if !model.current.body.jsonText.isEmpty,
                   !JSONFormatter.isValidJSON(model.current.body.jsonText) {
                    Label("Not valid JSON", systemImage: "exclamationmark.triangle.fill")
                        .font(.app(.caption))
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button("Format") {
                    if let pretty = JSONFormatter.prettyPrint(model.current.body.jsonText) {
                        model.current.body.jsonText = pretty
                    }
                }
                .buttonStyle(.link)
                .font(.app(.caption))
                Button("Minify") {
                    if let minified = JSONFormatter.minify(model.current.body.jsonText) {
                        model.current.body.jsonText = minified
                    }
                }
                .buttonStyle(.link)
                .font(.app(.caption))
            }
            .padding(.horizontal, 12)

            TextEditor(text: $model.current.body.jsonText)
                .font(.app(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(4)
        }
    }

    private var rawEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Syntax", selection: $model.current.body.rawLanguage) {
                    ForEach(RawLanguage.allCases, id: \.self) { language in
                        Text(language.rawValue.capitalized).tag(language)
                    }
                }
                .frame(maxWidth: 190)
                TextField(
                    model.current.body.rawLanguage.contentType,
                    text: $model.current.body.rawContentType
                )
                .textFieldStyle(.roundedBorder)
                .font(.app(.caption, design: .monospaced))
                .help("Overrides the Content-Type this syntax would send")
            }
            .padding(.horizontal, 12)

            TextEditor(text: $model.current.body.rawText)
                .font(.app(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(4)
        }
    }

    private var graphqlEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Query").font(.app(.caption)).foregroundStyle(.textMuted)
                .padding(.horizontal, 12)
            TextEditor(text: $model.current.body.graphqlQuery)
                .font(.app(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(4)
            Divider()
            HStack {
                Text("Variables (JSON)").font(.app(.caption)).foregroundStyle(.textMuted)
                if !model.current.body.graphqlVariables.isEmpty,
                   !JSONFormatter.isValidJSON(model.current.body.graphqlVariables) {
                    Text("· not valid JSON").font(.app(.caption)).foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 12)
            TextEditor(text: $model.current.body.graphqlVariables)
                .font(.app(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 70, maxHeight: 140)
                .padding(4)
        }
    }

    private var binaryEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("File path", text: $model.current.body.binaryFilePath)
                    .textFieldStyle(.roundedBorder)
                    .font(.app(.caption, design: .monospaced))
                Button("Choose…") {
                    if let url = ApiClientFilePanels.askOpen() {
                        model.current.body.binaryFilePath = url.path
                    }
                }
            }
            Text("The file's bytes are sent as the whole body.")
                .font(.app(.caption))
                .foregroundStyle(.textMuted)
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Auth

    private var authTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                authPicker(.segmented)
                authPicker(.menu)
            }

            if model.current.auth.type == .none, let inherited = model.inheritedAuth {
                Label(
                    "Inheriting \(ApiLabels.auth(inherited.type)) auth from the collection.",
                    systemImage: "arrow.down.left.circle"
                )
                .font(.app(.caption))
                .foregroundStyle(.textMuted)
                .padding(.horizontal, 12)
            }

            authFields.padding(.horizontal, 12)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func authPicker(_ style: some PickerStyle) -> some View {
        Picker("", selection: $model.current.auth.type) {
            ForEach(AuthType.allCases, id: \.self) { type in
                Text(ApiLabels.auth(type)).tag(type)
            }
        }
        .labelsHidden()
        .pickerStyle(style)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var authFields: some View {
        switch model.current.auth.type {
        case .none:
            Text("No authentication.").font(.app(.caption)).foregroundStyle(.textMuted)
        case .bearer:
            LabeledContent("Token") {
                SecureField("Bearer token", text: $model.current.auth.bearerToken)
                    .textFieldStyle(.roundedBorder)
            }
        case .basic:
            LabeledContent("Username") {
                TextField("Username", text: $model.current.auth.basicUsername)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Password") {
                SecureField("Password", text: $model.current.auth.basicPassword)
                    .textFieldStyle(.roundedBorder)
            }
        case .apiKey:
            LabeledContent("Key") {
                TextField("X-API-Key", text: $model.current.auth.apiKeyName)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Value") {
                SecureField("Key value", text: $model.current.auth.apiKeyValue)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Add to") {
                Picker("", selection: $model.current.auth.apiKeyLocation) {
                    Text("Header").tag(ApiKeyLocation.header)
                    Text("Query parameter").tag(ApiKeyLocation.query)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
        case .oauth2:
            LabeledContent("Access token") {
                SecureField("Token", text: $model.current.auth.oauth2Token)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Header prefix") {
                TextField("Bearer", text: $model.current.auth.oauth2HeaderPrefix)
                    .textFieldStyle(.roundedBorder)
            }
            Text("Paste a token you already have — Droidective doesn't run the OAuth grant flows.")
                .font(.app(.caption))
                .foregroundStyle(.textMuted)
        }
    }

    // MARK: - Tests

    private var testsTab: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tests").font(.app(.headline))
                if !model.assertionResults.isEmpty {
                    let summary = ApiAssertions.summary(model.assertionResults)
                    Text("\(summary.passed) passed, \(summary.failed) failed")
                        .font(.app(.caption))
                        .foregroundStyle(summary.failed == 0 ? .green : .orange)
                }
                Spacer()
                Button {
                    model.current.assertions.append(ApiAssertion())
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add a test")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if model.current.assertions.isEmpty {
                VStack(spacing: 6) {
                    Text("No tests yet.").font(.app(.caption)).foregroundStyle(.textMuted)
                    Text("Assert on the status code, response time, a header, or a JSON path.")
                        .font(.app(.caption2))
                        .foregroundStyle(.textMuted)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach($model.current.assertions) { $assertion in
                        ApiAssertionRow(
                            assertion: $assertion,
                            result: model.assertionResults.first { $0.id == assertion.id },
                            onDelete: {
                                model.current.assertions.removeAll { $0.id == assertion.id }
                            }
                        )
                    }
                }
                .listStyle(.plain)
                .translucentListBackground()
            }
        }
    }

    // MARK: - Settings

    private var settingsTab: some View {
        Form {
            Section("Network") {
                LabeledContent("Timeout") {
                    HStack {
                        TextField(
                            "60",
                            value: $model.current.settings.timeoutSeconds,
                            format: .number
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        Text("seconds — 0 waits as long as the server takes")
                            .font(.app(.caption))
                            .foregroundStyle(.textMuted)
                    }
                }
                Toggle("Follow redirects", isOn: $model.current.settings.followRedirects)
                if model.current.settings.followRedirects {
                    LabeledContent("Maximum redirects") {
                        TextField("10", value: $model.current.settings.maxRedirects, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                    }
                }
                Toggle("Send and store cookies", isOn: $model.current.settings.sendCookies)
            }

            Section("Security") {
                Toggle("Validate TLS certificates", isOn: $model.current.settings.validateTLS)
                if !model.current.settings.validateTLS {
                    Label(
                        "Certificate and hostname checks are off for this request. Only use it against a server you control.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.app(.caption))
                    .foregroundStyle(.orange)
                }
            }

            Section("Response") {
                LabeledContent("Keep at most") {
                    HStack {
                        TextField(
                            "32",
                            value: Binding(
                                get: { model.current.settings.maxResponseBytes / 1_048_576 },
                                set: { model.current.settings.maxResponseBytes = max(1, $0) * 1_048_576 }
                            ),
                            format: .number
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        Text("MB — anything larger is truncated")
                            .font(.app(.caption))
                            .foregroundStyle(.textMuted)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .translucentListBackground()
    }

    // MARK: - Code

    private var codeTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("", selection: $codeTarget) {
                    ForEach(CodeTarget.allCases) { target in
                        Text(target.label).tag(target)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.code(for: codeTarget), forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            ScrollView([.horizontal, .vertical]) {
                Text(model.code(for: codeTarget))
                    .font(.app(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.app(.caption))
            .foregroundStyle(.textMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Key/value editor

struct ApiKeyValueEditor: View {
    let title: String
    let placeholder: String
    @Binding var items: [ApiKeyValue]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.app(.headline))
                Spacer()
                Button { items.append(ApiKeyValue(key: "", value: "")) } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add a row")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if items.isEmpty {
                Text(placeholder)
                    .font(.app(.caption))
                    .foregroundStyle(.textMuted)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach($items) { $item in
                        HStack(spacing: 6) {
                            Toggle("", isOn: $item.enabled)
                                .labelsHidden()
                                .toggleStyle(.checkbox)
                                .help("Include this row")
                            TextField("Key", text: $item.key)
                                .textFieldStyle(.roundedBorder)
                                .font(.app(.caption, design: .monospaced))
                            TextField("Value", text: $item.value)
                                .textFieldStyle(.roundedBorder)
                                .font(.app(.caption, design: .monospaced))
                            Button {
                                items.removeAll { $0.id == item.id }
                            } label: {
                                Image(systemName: "minus.circle").foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .listStyle(.plain)
                .translucentListBackground()
            }
        }
    }
}

// MARK: - Multipart editor

struct ApiMultipartEditor: View {
    @Binding var fields: [ApiFormField]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Form Data").font(.app(.headline))
                Spacer()
                Button { fields.append(ApiFormField(key: "", value: "")) } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if fields.isEmpty {
                Text("No parts yet. Text parts and file parts can be mixed.")
                    .font(.app(.caption))
                    .foregroundStyle(.textMuted)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach($fields) { $field in
                        VStack(spacing: 4) {
                            HStack(spacing: 6) {
                                Toggle("", isOn: $field.enabled)
                                    .labelsHidden()
                                    .toggleStyle(.checkbox)
                                TextField("Key", text: $field.key)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.app(.caption, design: .monospaced))
                                Picker("", selection: $field.kind) {
                                    Text("Text").tag(FormFieldKind.text)
                                    Text("File").tag(FormFieldKind.file)
                                }
                                .labelsHidden()
                                .frame(width: 80)
                                Button {
                                    fields.removeAll { $0.id == field.id }
                                } label: {
                                    Image(systemName: "minus.circle").foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                            HStack(spacing: 6) {
                                TextField(
                                    field.kind == .file ? "File path" : "Value",
                                    text: $field.value
                                )
                                .textFieldStyle(.roundedBorder)
                                .font(.app(.caption, design: .monospaced))
                                if field.kind == .file {
                                    Button("Choose…") {
                                        if let url = ApiClientFilePanels.askOpen() {
                                            field.value = url.path
                                        }
                                    }
                                    .font(.app(.caption))
                                }
                                TextField("Content-Type", text: $field.contentType)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.app(.caption, design: .monospaced))
                                    .frame(width: 150)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.plain)
                .translucentListBackground()
            }
        }
    }
}

// MARK: - Assertion row

struct ApiAssertionRow: View {
    @Binding var assertion: ApiAssertion
    let result: AssertionResult?
    let onDelete: () -> Void

    private static let kinds = [
        ("statusCode", "Status code"),
        ("responseTimeMs", "Response time"),
        ("bodySize", "Body size"),
        ("bodyText", "Body text"),
        ("header", "Header"),
        ("jsonPath", "JSON path"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Toggle("", isOn: $assertion.enabled).labelsHidden().toggleStyle(.checkbox)

                Picker("", selection: kindBinding) {
                    ForEach(Self.kinds, id: \.0) { kind in
                        Text(kind.1).tag(kind.0)
                    }
                }
                .labelsHidden()
                .frame(width: 120)

                if !assertion.target.argument.isEmpty || needsArgument {
                    TextField(argumentPlaceholder, text: argumentBinding)
                        .textFieldStyle(.roundedBorder)
                        .font(.app(.caption, design: .monospaced))
                        .frame(width: 130)
                }

                Picker("", selection: $assertion.op) {
                    ForEach(AssertionOperator.allCases, id: \.self) { op in
                        Text(op.label).tag(op)
                    }
                }
                .labelsHidden()
                .frame(width: 130)

                if !assertion.op.isUnary {
                    TextField("Expected", text: $assertion.expected)
                        .textFieldStyle(.roundedBorder)
                        .font(.app(.caption, design: .monospaced))
                }

                Button { onDelete() } label: {
                    Image(systemName: "minus.circle").foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
            }

            if let result {
                HStack(spacing: 4) {
                    Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.passed ? .green : .red)
                        .font(.app(.caption2))
                    Text(result.passed ? "Passed" : "Failed — got \(result.detail)")
                        .font(.app(.caption2))
                        .foregroundStyle(.textMuted)
                        .textSelection(.enabled)
                }
                .padding(.leading, 24)
            }
        }
        .padding(.vertical, 2)
    }

    private var needsArgument: Bool {
        assertion.target.kindName == "header" || assertion.target.kindName == "jsonPath"
    }

    private var argumentPlaceholder: String {
        assertion.target.kindName == "header" ? "Content-Type" : "data.items[0].id"
    }

    private var kindBinding: Binding<String> {
        Binding(
            get: { assertion.target.kindName },
            set: { assertion.target = .make(kindName: $0, argument: assertion.target.argument) }
        )
    }

    private var argumentBinding: Binding<String> {
        Binding(
            get: { assertion.target.argument },
            set: { assertion.target = .make(kindName: assertion.target.kindName, argument: $0) }
        )
    }
}

// MARK: - Labels

enum ApiLabels {
    static func body(_ type: BodyType) -> String {
        switch type {
        case .none: return "None"
        case .json: return "JSON"
        case .formUrlEncoded: return "Form"
        case .multipart: return "Form Data"
        case .raw: return "Raw"
        case .graphql: return "GraphQL"
        case .binary: return "Binary"
        }
    }

    static func auth(_ type: AuthType) -> String {
        switch type {
        case .none: return "None"
        case .bearer: return "Bearer"
        case .basic: return "Basic"
        case .apiKey: return "API Key"
        case .oauth2: return "OAuth 2"
        }
    }
}

// MARK: - Panels

@MainActor
enum ApiClientFilePanels {
    static func askOpen() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp?.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func askSave(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        NSApp?.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }
}
