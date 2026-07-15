//
//  QuickNotesView.swift
//  NotchLand
//

import SwiftUI

struct QuickNotesView: View {
    @EnvironmentObject private var notes: QuickNotesController
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 182)

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(width: 1)
                .padding(.vertical, 10)

            editor
        }
        .padding(.horizontal, 18)
        .padding(.top, 35)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Notes", systemImage: "note.text")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                Button {
                    _ = notes.createNote()
                    isEditorFocused = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 24, height: 24)
                        .background(.white.opacity(0.09), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New note")
            }
            .padding(.horizontal, 2)

            if notes.notes.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("No notes yet")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 6) {
                        ForEach(notes.notes) { note in
                            noteRow(note)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.trailing, 12)
    }

    private func noteRow(_ note: QuickNote) -> some View {
        let isSelected = notes.selectedID == note.id

        return Button {
            notes.select(note)
            isEditorFocused = true
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if note.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.orange)
                    }
                    Text(note.title)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                }
                Text(note.preview)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(isSelected ? .white.opacity(0.66) : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                isSelected ? Color.white.opacity(0.16) : Color.white.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(note.isPinned ? "Unpin" : "Pin") { notes.togglePinned(note) }
            Button("Copy") { notes.copy(note) }
            Divider()
            Button("Delete", role: .destructive) { notes.delete(note) }
        }
    }

    @ViewBuilder
    private var editor: some View {
        if let note = notes.selectedNote {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 9) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(note.title)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .lineLimit(1)
                        Text(note.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    editorButton(note.isPinned ? "pin.slash.fill" : "pin.fill", label: note.isPinned ? "Unpin" : "Pin") {
                        notes.togglePinned(note)
                    }
                    editorButton("doc.on.doc.fill", label: "Copy") { notes.copy(note) }
                    editorButton("trash.fill", label: "Delete", role: .destructive) { notes.delete(note) }
                }

                TextEditor(text: contentBinding(for: note))
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .focused($isEditorFocused)
                    .overlay(alignment: .topLeading) {
                        if note.content.isEmpty {
                            Text("Write something…")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.top, 1)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
            }
            .padding(.leading, 14)
            .id(note.id)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        } else {
            VStack(spacing: 10) {
                Image(systemName: "note.text.badge.plus")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.secondary)
                Button("Create a note") {
                    _ = notes.createNote()
                    isEditorFocused = true
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 15)
                .frame(height: 30)
                .background(.white, in: Capsule())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func contentBinding(for note: QuickNote) -> Binding<String> {
        Binding(
            get: { notes.notes.first(where: { $0.id == note.id })?.content ?? "" },
            set: { notes.updateContent(id: note.id, content: $0) }
        )
    }

    private func editorButton(
        _ symbol: String,
        label: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 23, height: 23)
                .background(.white.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
