#if canImport(SwiftUI)
import SwiftUI

/// 倒数日 / 纪念日列表页
struct CountdownView: View {
    @Environment(CountdownStore.self) private var store
    @State private var showingEditor = false
    @State private var editingEvent: CountdownEvent?

    private let today = Date()

    var body: some View {
        List {
            if store.events.isEmpty {
                ContentUnavailableView(
                    "还没有倒数日",
                    systemImage: "hourglass",
                    description: Text("点击右上角添加生日、纪念日或重要日期")
                )
            } else {
                ForEach(store.events) { event in
                    CountdownRow(event: event, today: today)
                        .contentShape(Rectangle())
                        .onTapGesture { editingEvent = event }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                store.delete(id: event.id)
                            } label: { Label("删除", systemImage: "trash") }
                        }
                }
            }
        }
        .navigationTitle("倒数日")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editingEvent = nil; showingEditor = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .touchTarget()
            }
        }
        .sheet(isPresented: $showingEditor) {
            CountdownEditor(event: editingEvent)
        }
        .sheet(item: $editingEvent) { event in
            CountdownEditor(event: event)
        }
    }
}

// MARK: - 行

private struct CountdownRow: View {
    let event: CountdownEvent
    let today: Date

    var body: some View {
        HStack(spacing: 12) {
            Text(event.emoji)
                .font(.system(size: 32))
                .frame(width: 48, height: 48)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.label)
                Text(event.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(Color.secondaryLabel)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(event.displayText(today: today))
                    .font(.headline)
                    .foregroundStyle(abs(event.daysFrom(today: today)) <= 7 ? Color.festiveRed : Color.label)
                Text(event.kind.label)
                    .font(.caption2)
                    .foregroundStyle(Color.tertiaryLabel)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title) \(event.displayText(today: today))")
    }
}

// MARK: - 编辑器

private struct CountdownEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CountdownStore.self) private var store

    @State private var title = ""
    @State private var date = Date()
    @State private var kind: CountdownKind = .countdown
    @State private var emoji = "📅"
    @State private var note = ""

    private let editing: CountdownEvent?
    private let emojis = ["📅", "🎂", "💍", "🎓", "🏖️", "✈️", "🏠", "🎉", "❤️", "🎯", "📝", "🎁"]

    init(event: CountdownEvent?) {
        editing = event
        _title = State(initialValue: event?.title ?? "")
        _date = State(initialValue: event?.date ?? Date().addingMonths(1))
        _kind = State(initialValue: event?.kind ?? .countdown)
        _emoji = State(initialValue: event?.emoji ?? "📅")
        _note = State(initialValue: event?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("标题", text: $title)
                    Picker("类型", selection: $kind) {
                        ForEach(CountdownKind.allCases, id: \.self) { k in
                            Label(k.label, systemImage: k.icon).tag(k)
                        }
                    }
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                }

                Section("图标") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                        ForEach(emojis, id: \.self) { e in
                            Text(e)
                                .font(.system(size: 28))
                                .frame(width: 44, height: 44)
                                .background(emoji == e ? Color.accentColor.opacity(0.2) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .onTapGesture { emoji = e }
                        }
                    }
                }

                Section("备注（可选）") {
                    TextField("添加备注", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(editing == nil ? "新建倒数日" : "编辑倒数日")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                        .font(.body.weight(.semibold))
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func save() {
        let event = CountdownEvent(
            id: editing?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespaces),
            date: date,
            kind: kind,
            emoji: emoji,
            note: note.isEmpty ? nil : note
        )
        if editing != nil {
            store.update(event)
        } else {
            store.add(event)
        }
        dismiss()
    }
}
#endif
