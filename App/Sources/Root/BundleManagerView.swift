import ADBKit
import SwiftUI

/// Add, edit, and remove saved bundles; pick package ids straight from the
/// device's installed third-party apps.
struct BundleManagerView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var nickname = ""
    @State private var packageId = ""
    @State private var editingBundle: AppBundle?
    @State private var pendingDelete: AppBundle?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Saved Bundles")
                .font(.app(.headline))

            if state.bundles.isEmpty {
                Text("Save an app's bundle id once, then pick it from dropdowns across the app.")
                    .font(.app(.footnote))
                    .foregroundStyle(.textMuted)
            } else {
                List(state.bundles) { bundle in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(bundle.nickname)
                            Text(bundle.packageId)
                                .font(.app(.footnote))
                                .foregroundStyle(.textMuted)
                        }
                        Spacer()
                        Button {
                            editingBundle = bundle
                            nickname = bundle.nickname
                            packageId = bundle.packageId
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(IconButtonStyle())
                        Button {
                            pendingDelete = bundle
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(IconButtonStyle())
                        .accessibilityLabel("Delete \(bundle.nickname)")
                    }
                }
                .frame(minHeight: 120, maxHeight: 200)
            }

            Divider()

            Text(editingBundle == nil ? "Add new bundle" : "Edit bundle")
                .font(.app(.subheadline).bold())
            TextField("Nickname (e.g. My App)", text: $nickname)
                .brandField()
            TextField("Package id (e.g. com.myapp)", text: $packageId)
                .brandField()

            HStack {
                Spacer()
                Button("Close") { dismiss() }
                if editingBundle != nil {
                    Button("Cancel Edit") {
                        editingBundle = nil
                        nickname = ""
                        packageId = ""
                    }
                }
                Button(editingBundle == nil ? "Add" : "Save") {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .disabled(packageId.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 440)
        .confirmationDialog(
            "Delete “\(pendingDelete?.nickname ?? "")”?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let target = pendingDelete { state.removeBundle(id: target.id) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This removes the saved bundle. This can't be undone.")
        }
    }

    private func submit() {
        let trimmedPackage = packageId.trimmingCharacters(in: .whitespaces)
        let trimmedNickname = nickname.trimmingCharacters(in: .whitespaces)
        if var bundle = editingBundle {
            bundle.nickname = trimmedNickname.isEmpty ? trimmedPackage : trimmedNickname
            bundle.packageId = trimmedPackage
            state.updateBundle(bundle)
            state.selectBundle(bundle.id)
        } else {
            state.addBundle(nickname: trimmedNickname, packageId: trimmedPackage)
        }
        dismiss()
    }
}
