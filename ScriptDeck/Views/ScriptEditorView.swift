import SwiftUI
import AppKit

struct ScriptEditorView: View {
    let mode: EditorMode
    let onSave: (ScriptConfiguration) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var directory: String
    @State private var command: String
    @State private var validationErrors: ScriptValidationErrors

    init(
        mode: EditorMode,
        initialValidationErrors: ScriptValidationErrors = ScriptValidationErrors(),
        onSave: @escaping (ScriptConfiguration) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.onSave = onSave
        self.onCancel = onCancel

        switch mode {
        case .add:
            _name = State(initialValue: "")
            _directory = State(initialValue: "")
            _command = State(initialValue: "")
        case .edit(let config):
            _name = State(initialValue: config.name)
            _directory = State(initialValue: config.directory)
            _command = State(initialValue: config.command)
        }

        _validationErrors = State(initialValue: initialValidationErrors)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider().overlay(Theme.subtleBorder)

            VStack(alignment: .leading, spacing: 18) {
                nameField
                directoryField
                commandField
            }
            .padding(24)

            Divider().overlay(Theme.subtleBorder)
            footerSection
        }
        .frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.sheetBackground)
        .preferredColorScheme(.dark)
    }

    // MARK: - Header & Footer

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(mode.title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.primaryText)

            if let subtitle = mode.subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var footerSection: some View {
        HStack(spacing: 10) {
            Spacer()

            Button {
                onCancel()
            } label: {
                Text("Cancel")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(
                DeckActionButtonStyle(
                    background: Theme.addButtonBackground,
                    hoverBackground: Theme.addButtonHover,
                    foreground: Theme.primaryText,
                    cornerRadius: 8,
                    borderColor: Theme.subtleBorder,
                    horizontalPadding: 16,
                    minHeight: 34
                )
            )
            .keyboardShortcut(.cancelAction)

            Button {
                submit()
            } label: {
                Text(mode.submitButtonTitle)
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(
                DeckActionButtonStyle(
                    background: Theme.startButtonBackground,
                    hoverBackground: Theme.startButtonHover,
                    foreground: Theme.startButtonText,
                    cornerRadius: 8,
                    horizontalPadding: 16,
                    minHeight: 34
                )
            )
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Form Fields

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Name")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.primaryText)

            TextField("My Project", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.primaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(fieldBackground(hasError: validationErrors.nameError != nil))

            if let error = validationErrors.nameError {
                errorText(error)
            }
        }
    }

    private var directoryField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Directory")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.primaryText)

            HStack(spacing: 8) {
                TextField("/Users/me/project", text: $directory)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.primaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(fieldBackground(hasError: validationErrors.directoryError != nil))

                Button {
                    chooseDirectory()
                } label: {
                    Text("Choose…")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(
                    DeckActionButtonStyle(
                        background: Theme.addButtonBackground,
                        hoverBackground: Theme.addButtonHover,
                        foreground: Theme.primaryText,
                        cornerRadius: 8,
                        borderColor: Theme.subtleBorder,
                        horizontalPadding: 14,
                        minHeight: 33
                    )
                )
            }

            if let error = validationErrors.directoryError {
                errorText(error)
            }
        }
    }

    private var commandField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Command")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.primaryText)

            TextField("npm run dev", text: $command)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.primaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(fieldBackground(hasError: validationErrors.commandError != nil))

            if let error = validationErrors.commandError {
                errorText(error)
            }
        }
    }

    // MARK: - Helpers

    private func fieldBackground(hasError: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Theme.inputBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(hasError ? Theme.failed : Theme.subtleBorder, lineWidth: 1)
            )
    }

    private func errorText(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundStyle(Theme.failed)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose Directory"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true

        let trimmed = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, FileManager.default.fileExists(atPath: trimmed) {
            panel.directoryURL = URL(fileURLWithPath: trimmed, isDirectory: true)
        }

        if panel.runModal() == .OK, let url = panel.url {
            directory = url.path
            validationErrors.directoryError = nil
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                name = url.lastPathComponent
            }
        }
    }

    private func submit() {
        let errors = ScriptValidator.validate(
            name: name,
            directory: directory,
            command: command
        )

        validationErrors = errors
        guard errors.isValid else {
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDir = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)

        let existingID: UUID
        switch mode {
        case .add:
            existingID = UUID()
        case .edit(let existing):
            existingID = existing.id
        }

        let configuration = ScriptConfiguration(
            id: existingID,
            name: trimmedName,
            directory: cleanDir,
            command: cleanCommand
        )

        onSave(configuration)
    }
}
