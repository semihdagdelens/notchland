import SwiftUI

/// Notlar sekmesi: solda Hatırlatıcılar, sağda Notlar uygulamasıyla eşitlenen hızlı notlar.
struct NotesTabView: View {
    let state: NotchState
    let reminders: RemindersService
    let notes: NotesService

    /// Klavyeyle gezinmede ↓ ↑ ile seçilen eylem; Return onu başlatır.
    enum Target { case newReminder, newNote }
    @State private var target: Target?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RemindersColumn(state: state, reminders: reminders, isTargeted: isTargeted(.newReminder))
                .frame(maxWidth: .infinity)
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 1)
            NotesColumn(state: state, notes: notes, isTargeted: isTargeted(.newNote))
                .frame(maxWidth: .infinity)
        }
        .onChange(of: state.keyCommand) { _, command in
            let canAddReminder = reminders.access == .granted
            switch command?.kind {
            case .down: target = target == nil && canAddReminder ? .newReminder : .newNote
            case .up: target = target == .newNote && canAddReminder ? .newReminder : nil
            default: break
            }
        }
        .onAppear {
            reminders.activate()
            notes.refresh()
        }
        .onDisappear {
            state.isEditingText = false
            NotchPanel.releaseKeyFocus()
        }
    }

    private func isTargeted(_ candidate: Target) -> Bool {
        state.isKeyboardActive && target == candidate
    }
}

/// Klavyeyle seçilen öğenin çerçevesi.
private struct TargetOutline: ViewModifier {
    let isTargeted: Bool
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Color.white.opacity(isTargeted ? 0.5 : 0), lineWidth: 1)
                .animation(.easeOut(duration: 0.12), value: isTargeted)
        )
    }
}

private struct ColumnHeader<Accessory: View>: View {
    let title: String
    let symbol: String
    let onOpen: () -> Void
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onOpen) {
                Label(title, systemImage: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("\(title) uygulamasında aç")
            Spacer(minLength: 0)
            accessory
        }
    }
}

// MARK: - Hatırlatıcılar

private struct RemindersColumn: View {
    let state: NotchState
    let reminders: RemindersService
    let isTargeted: Bool

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ColumnHeader(title: "Hatırlatıcılar", symbol: "checklist", onOpen: reminders.openApp) {
                if !reminders.items.isEmpty {
                    Text("\(reminders.items.filter { !$0.isCompleted }.count)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            switch reminders.access {
            case .denied:
                Text("Hatırlatıcılar izni verilmedi")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            case .unknown:
                Spacer(minLength: 0)
            case .granted:
                if reminders.items.isEmpty {
                    Text("Bekleyen hatırlatıcı yok")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(reminders.items) { item in
                                ReminderRow(item: item) { reminders.toggle(item) }
                            }
                        }
                    }
                }
                TextField("Yeni hatırlatıcı", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                    .modifier(TargetOutline(isTargeted: isTargeted && !isFocused, cornerRadius: 6))
                    .focused($isFocused)
                    .onSubmit {
                        reminders.add(draft)
                        draft = ""
                    }
                    .onExitCommand {
                        draft = ""
                        isFocused = false
                        NotchPanel.releaseKeyFocus()
                    }
            }
        }
        .onChange(of: isFocused) { _, focused in state.isEditingText = focused }
        .onChange(of: state.keyCommand) { _, command in
            if command?.kind == .enter && isTargeted { isFocused = true }
        }
    }
}

private struct ReminderRow: View {
    let item: RemindersService.Item
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(item.isCompleted ? Color(nsColor: item.color) : .white.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 0) {
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                if let due = item.due {
                    Text(Self.format(due, hasTime: item.hasTime))
                        .font(.system(size: 10))
                        .foregroundStyle(item.isOverdue ? Color.red : .secondary)
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: item.isCompleted)
    }

    private static func format(_ date: Date, hasTime: Bool) -> String {
        let calendar = Calendar.current
        let time = hasTime ? " " + date.formatted(date: .omitted, time: .shortened) : ""
        if calendar.isDateInToday(date) { return "Bugün" + time }
        if calendar.isDateInTomorrow(date) { return "Yarın" + time }
        if calendar.isDateInYesterday(date) { return "Dün" + time }
        return date.formatted(.dateTime.day().month(.abbreviated)) + time
    }
}

// MARK: - Notlar

private struct NotesColumn: View {
    let state: NotchState
    let notes: NotesService
    let isTargeted: Bool

    /// Düzenlenen not: `.some(nil)` yeni not, `.some(id)` mevcut not.
    @State private var editing: String?? = nil
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ColumnHeader(title: "Notlar", symbol: "note.text", onOpen: { notes.open(id: nil) }) {
                if editing == nil {
                    Button {
                        begin(nil, text: "")
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(3)
                            .modifier(TargetOutline(isTargeted: isTargeted, cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .help("Yeni not")
                }
            }

            if let editing {
                editor(for: editing)
            } else if let error = notes.error, notes.notes.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if notes.notes.isEmpty {
                Text(notes.isLoading ? "Yükleniyor…" : "Not yok. Notlar'daki “\(NotesService.folderName)” klasörüyle eşitlenir.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(notes.notes) { note in
                            NoteRow(note: note)
                                .contentShape(Rectangle())
                                .onTapGesture { begin(note.id, text: note.text) }
                                .contextMenu {
                                    Button("Notlar'da Aç") { notes.open(id: note.id) }
                                    Button("Sil", role: .destructive) { notes.delete(id: note.id) }
                                }
                        }
                    }
                }
            }
        }
        .onChange(of: isFocused) { _, focused in state.isEditingText = focused }
        .onChange(of: state.keyCommand) { _, command in
            if command?.kind == .enter && isTargeted && editing == nil { begin(nil, text: "") }
        }
    }

    private func editor(for id: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            TextEditor(text: $draft)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                .focused($isFocused)
                .onExitCommand(perform: commit)
            HStack(spacing: 12) {
                if let id {
                    Button {
                        notes.delete(id: id)
                        end()
                    } label: {
                        Image(systemName: "trash").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Sil")
                }
                Spacer(minLength: 0)
                Button("Vazgeç", action: end)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Button("Kaydet", action: commit)
                    .buttonStyle(.plain)
                    .fontWeight(.semibold)
            }
            .font(.system(size: 11))
        }
    }

    private func begin(_ id: String?, text: String) {
        draft = text
        editing = .some(id)
        DispatchQueue.main.async { isFocused = true }
    }

    private func commit() {
        if let editing {
            let original = editing.flatMap { id in notes.notes.first { $0.id == id }?.text }
            if draft != original { notes.save(id: editing, text: draft) }
        }
        end()
    }

    private func end() {
        editing = nil
        draft = ""
        isFocused = false
        NotchPanel.releaseKeyFocus()
    }
}

private struct NoteRow: View {
    let note: NotesService.Note

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(note.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(note.modified, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            if !note.preview.isEmpty {
                Text(note.preview)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
