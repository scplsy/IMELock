import SwiftUI

/// One value shared by the slider and a validated numeric editor.
struct DelaySettingView: View {
    @Binding var milliseconds: Int
    @State private var input = ""
    @State private var inputError: String?
    @FocusState private var isEditing: Bool

    private let range = ConfigurationStore.activationDelayRange

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("切换应用后等待")
                    .font(.headline)
                Spacer()
                TextField("200", text: $input)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(width: 72)
                    .focused($isEditing)
                    .accessibilityLabel("检测延迟，毫秒")
                    .onSubmit(commitInput)
                    .onExitCommand {
                        input = String(milliseconds)
                        inputError = nil
                        isEditing = false
                    }
                Text("毫秒")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                Slider(value: Binding(
                    get: { Double(milliseconds) },
                    set: { select(Int(($0 / 10).rounded()) * 10) }
                ), in: Double(range.lowerBound)...Double(range.upperBound))
                .labelsHidden()
                .accessibilityLabel("检测延迟")
                .accessibilityValue("\(milliseconds) 毫秒")
                HStack {
                    Text("50 ms")
                    Spacer()
                    Text("1000 ms")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("恢复默认") {
                    select(ConfigurationStore.defaultActivationDelayMilliseconds)
                }
                .controlSize(.small)
                .disabled(milliseconds == ConfigurationStore.defaultActivationDelayMilliseconds)
                .help("恢复为 200 毫秒")
            }

            if let inputError {
                Label(inputError, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
        .onAppear { input = String(milliseconds) }
        .onChange(of: milliseconds) { _, value in
            input = String(value)
            inputError = nil
        }
        .onChange(of: isEditing) { _, editing in
            if !editing { commitInput() }
        }
    }

    private func select(_ value: Int) {
        input = String(value)
        inputError = nil
        isEditing = false
        if milliseconds != value { milliseconds = value }
    }

    private func commitInput() {
        guard let value = Int(input.trimmingCharacters(in: .whitespacesAndNewlines)),
              range.contains(value) else {
            inputError = "请输入 50–1000 之间的整数，当前设置仍为 \(milliseconds) 毫秒。"
            return
        }
        select(value)
    }
}
