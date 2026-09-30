import SwiftUI

/// Medis-style table editor for hash / list / set / zset values.
/// Left: a two-column table (Field/Content) with a header row, zebra striping,
/// row selection and hover-delete. Right: an inspector panel to edit the
/// selected row's field/content (multi-line) and Save. Bottom: add / delete.
struct StructuredValueEditor: View {
    let typedValue: TypedKeyValue
    /// Case-insensitive filter on field/value; empty shows all rows.
    var filter: String = ""
    @EnvironmentObject var viewModel: KeyBrowserViewModel

    // Selection + inspector edit buffers
    @State private var selectedID: Int?
    @State private var editField = ""
    @State private var editContent = ""
    @State private var editScore = ""

    // Add dialog state
    @State private var showAdd = false
    @State private var addField = ""
    @State private var addValue = ""
    @State private var addScore = ""

    // Delete confirmation state
    @State private var showDeleteConfirm = false
    @State private var pendingDelete: (() -> Void)?
    @State private var deleteLabel = ""

    /// One table row, normalized across the four collection types.
    private struct RowModel: Identifiable {
        let id: Int
        let leftText: String?     // hash field / list index / zset score; nil for set
        let content: String       // value or member
        let score: Double?        // zset only
    }

    var body: some View {
        HStack(spacing: 0) {
            // Table
            VStack(spacing: 0) {
                header
                Divider()
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { r in
                            tableRow(r)
                        }
                    }
                }
                Divider()
                addBar
            }
            .frame(maxWidth: .infinity)

            // Inspector (only when a row is selected)
            if let id = selectedID, rows.contains(where: { $0.id == id }) {
                Divider()
                inspector
                    .frame(width: 280)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: selectedID)
        .onChange(of: typedValue) { _ in selectedID = nil }
        .alert(addLabel, isPresented: $showAdd) {
            addFields
            Button("Add") { commitAdd() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete \(deleteLabel)?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let action = pendingDelete { action() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the element from the key. This cannot be undone.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Theme.spacing.lg) {
            if let leftTitle = columnTitles.left {
                Text(leftTitle.uppercased())
                    .frame(width: leftColWidth, alignment: .leading)
            }
            Text(columnTitles.right.uppercased())
            Spacer(minLength: 0)
        }
        .font(.system(size: 10, weight: .bold, design: .rounded))
        .tracking(0.8)
        .foregroundColor(Theme.colors.textTertiary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.colors.surfaceHover)
    }

    // MARK: Row

    @ViewBuilder
    private func tableRow(_ r: RowModel) -> some View {
        let isSelected = selectedID == r.id
        HStack(spacing: Theme.spacing.lg) {
            if let left = r.leftText {
                Text(left)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(isSelected ? .white : Theme.colors.jsonKey)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: leftColWidth, alignment: .leading)
            }
            Text(r.content)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(isSelected ? .white : Theme.colors.text)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: Theme.spacing.md)
            Button {
                confirmDelete(deleteDescription(r)) { await deleteRow(r) }
            } label: {
                Image(systemName: "trash").font(.system(size: 11))
                    .foregroundColor(isSelected ? .white : Theme.colors.error)
            }
            .buttonStyle(.plain).handCursor()
            .help("Delete")
            .opacity(isSelected ? 1 : 0.55)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isSelected ? Theme.colors.primary
                    : (r.id.isMultiple(of: 2) ? Theme.colors.surface : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { select(r) }
        .handCursor()
    }

    // MARK: Inspector

    private var inspector: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.md) {
            if hasFieldColumn {
                Text(fieldLabel)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.colors.textTertiary)
                if isFieldEditable {
                    TextField("", text: fieldBinding)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(Theme.spacing.sm)
                        .background(Theme.colors.codeBackground)
                        .cornerRadius(Theme.sizes.smallCornerRadius)
                } else {
                    Text(editField)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(Theme.colors.textSecondary)
                        .textSelection(.enabled)
                }
            }

            Text("Content")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.colors.textTertiary)
            TextEditor(text: $editContent)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(Theme.spacing.xs)
                .background(Theme.colors.codeBackground)
                .cornerRadius(Theme.sizes.smallCornerRadius)
                .frame(minHeight: 120)

            HStack {
                CopyButton(value: editContent, help: "Copy content")
                Spacer()
                Button("Save") { commitInspector() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(!inspectorDirty)
            }
        }
        .padding(Theme.spacing.lg)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.colors.background)
    }

    private var addBar: some View {
        HStack {
            Button(action: { resetAddFields(); showAdd = true }) {
                HStack(spacing: Theme.spacing.sm) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                    Text(addLabel)
                }
            }
            .buttonStyle(GhostButtonStyle())
            Spacer()
            Text("\(rows.count) \(rows.count == 1 ? "row" : "rows")")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.colors.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: Row model + column config

    private var rows: [RowModel] {
        let all: [RowModel]
        switch typedValue {
        case .hash(let fields):
            all = fields.enumerated().map { RowModel(id: $0.offset, leftText: $0.element.field, content: $0.element.value, score: nil) }
        case .list(let items):
            all = items.enumerated().map { RowModel(id: $0.offset, leftText: "\($0.offset)", content: $0.element, score: nil) }
        case .set(let members):
            all = members.enumerated().map { RowModel(id: $0.offset, leftText: nil, content: $0.element, score: nil) }
        case .zset(let members):
            all = members.enumerated().map { RowModel(id: $0.offset, leftText: formatScore($0.element.score), content: $0.element.member, score: $0.element.score) }
        default:
            all = []
        }
        // IDs stay the original indices (edit/delete rely on them) even when filtered.
        let f = filter.trimmingCharacters(in: .whitespaces)
        guard !f.isEmpty else { return all }
        return all.filter {
            ($0.leftText?.localizedCaseInsensitiveContains(f) ?? false)
                || $0.content.localizedCaseInsensitiveContains(f)
        }
    }

    private var columnTitles: (left: String?, right: String) {
        switch typedValue {
        case .hash: return ("Field", "Content")
        case .list: return ("Index", "Value")
        case .set: return (nil, "Member")
        case .zset: return ("Score", "Member")
        default: return (nil, "Value")
        }
    }

    private var leftColWidth: CGFloat {
        switch typedValue {
        case .hash: return 170
        case .list, .zset: return 70
        default: return 0
        }
    }

    /// The inspector shows a field/identity box for all but list (index is fixed).
    private var hasFieldColumn: Bool {
        switch typedValue {
        case .hash, .list, .zset: return true
        default: return false
        }
    }

    private var fieldLabel: String {
        switch typedValue {
        case .hash: return "Field"
        case .list: return "Index"
        case .zset: return "Score"
        default: return "Field"
        }
    }

    /// Hash field and zset score are editable; list index is not.
    private var isFieldEditable: Bool {
        switch typedValue {
        case .hash, .zset: return true
        default: return false
        }
    }

    private var fieldBinding: Binding<String> {
        switch typedValue {
        case .zset: return $editScore
        default: return $editField
        }
    }

    // MARK: Selection + inspector commit

    private func select(_ r: RowModel) {
        selectedID = r.id
        editField = r.leftText ?? ""
        editContent = r.content
        editScore = r.score.map(formatScore) ?? ""
    }

    private var selectedRow: RowModel? { rows.first { $0.id == selectedID } }

    private var inspectorDirty: Bool {
        guard let r = selectedRow else { return false }
        switch typedValue {
        case .hash:
            return editContent != r.content || editField != (r.leftText ?? "")
        case .list:
            return editContent != r.content
        case .set:
            return editContent != r.content
        case .zset:
            return editContent != r.content || editScore != (r.score.map(formatScore) ?? "")
        default:
            return false
        }
    }

    private func commitInspector() {
        guard let r = selectedRow, inspectorDirty else { return }
        switch typedValue {
        case .hash:
            let oldField = r.leftText ?? ""
            let newField = editField.trimmingCharacters(in: .whitespaces)
            guard !newField.isEmpty else { ToastCenter.shared.error("Field required"); return }
            let content = editContent
            Task {
                if newField != oldField { await viewModel.deleteHashField(oldField) }
                await viewModel.setHashField(newField, value: content)
            }
        case .list:
            Task { await viewModel.setListIndex(r.id, value: editContent) }
        case .set:
            let old = r.content
            let new = editContent
            guard !new.isEmpty else { ToastCenter.shared.error("Member required"); return }
            Task {
                if new != old { await viewModel.removeSetMember(old) }
                await viewModel.addSetMember(new)
            }
        case .zset:
            guard let score = Double(editScore) else { ToastCenter.shared.error("Score must be a number"); return }
            let oldMember = r.content
            let newMember = editContent
            guard !newMember.isEmpty else { ToastCenter.shared.error("Member required"); return }
            Task {
                if newMember != oldMember { await viewModel.removeZSetMember(oldMember) }
                await viewModel.addZSetMember(newMember, score: score)
            }
        default:
            break
        }
    }

    // MARK: Delete

    private func deleteDescription(_ r: RowModel) -> String {
        switch typedValue {
        case .hash: return "field \"\(r.leftText ?? "")\""
        case .list: return "element at index \(r.id)"
        default: return "member \"\(r.content)\""
        }
    }

    private func deleteRow(_ r: RowModel) async {
        switch typedValue {
        case .hash: await viewModel.deleteHashField(r.leftText ?? "")
        case .list: await viewModel.removeListIndex(r.id)
        case .set: await viewModel.removeSetMember(r.content)
        case .zset: await viewModel.removeZSetMember(r.content)
        default: break
        }
        selectedID = nil
    }

    /// Stage a delete behind a confirmation alert.
    private func confirmDelete(_ label: String, _ action: @escaping () async -> Void) {
        deleteLabel = label
        pendingDelete = { Task { await action() } }
        showDeleteConfirm = true
    }

    // MARK: Add dialog fields per type

    @ViewBuilder
    private var addFields: some View {
        switch typedValue {
        case .hash:
            TextField("Field", text: $addField)
            TextField("Value", text: $addValue)
        case .zset:
            TextField("Score", text: $addScore)
            TextField("Member", text: $addValue)
        default:
            TextField("Value", text: $addValue)
        }
    }

    private var addLabel: String {
        switch typedValue {
        case .hash: return "Add field"
        case .list: return "Append element"
        case .set: return "Add member"
        case .zset: return "Add member"
        default: return "Add"
        }
    }

    private func commitAdd() {
        switch typedValue {
        case .hash:
            guard !addField.isEmpty else { return }
            Task { await viewModel.setHashField(addField, value: addValue) }
        case .list:
            Task { await viewModel.appendList(addValue) }
        case .set:
            guard !addValue.isEmpty else { return }
            Task { await viewModel.addSetMember(addValue) }
        case .zset:
            guard let score = Double(addScore), !addValue.isEmpty else { return }
            Task { await viewModel.addZSetMember(addValue, score: score) }
        default:
            break
        }
    }

    private func resetAddFields() { addField = ""; addValue = ""; addScore = "" }

    private func formatScore(_ s: Double) -> String {
        s.truncatingRemainder(dividingBy: 1) == 0 ? String(Int64(s)) : String(s)
    }
}
