//
//  TodoView.swift
//  NotchLand
//

import SwiftUI

struct TodoView: View {
    @EnvironmentObject private var todo: TodoController
    @State private var draft = ""
    @State private var showsArchive = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            header

            if !showsArchive {
                addField
            }

            taskContent
        }
        .padding(.horizontal, 28)
        .padding(.top, 36)
        .padding(.bottom, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { todo.archiveEligibleItems() }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "checklist")
                .foregroundStyle(.green)
            Text(showsArchive ? "Task Archive" : "Tasks")
                .font(.system(size: 15, weight: .bold, design: .rounded))

            if !showsArchive {
                Text("\(todo.remainingCount) left")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(.white.opacity(0.07), in: Capsule())
            }

            Spacer()

            if !showsArchive, todo.activeItems.contains(where: \.isCompleted) {
                Button("Archive done") { todo.archiveCompleted() }
                    .buttonStyle(.plain)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Button {
                withAnimation(NotchMotion.selection) { showsArchive.toggle() }
            } label: {
                Label(showsArchive ? "Tasks" : "Archive", systemImage: showsArchive ? "checklist" : "archivebox")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(.white.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var addField: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.green)
            TextField("Add a task…", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .focused($isInputFocused)
                .onSubmit(addTask)
            Button(action: addTask) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 22, height: 22)
                    .background(.white, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1)
        }
        .padding(.horizontal, 11)
        .frame(height: 34)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(.white.opacity(isInputFocused ? 0.2 : 0.07), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var taskContent: some View {
        let displayedItems = showsArchive ? todo.archivedItems : todo.activeItems

        if displayedItems.isEmpty {
            VStack(spacing: 7) {
                Image(systemName: showsArchive ? "archivebox" : "checkmark.circle")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(showsArchive ? "Archive is empty" : "Everything is clear")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical) {
                LazyVStack(spacing: 6) {
                    ForEach(displayedItems) { item in
                        taskRow(item)
                            .transition(.scale(scale: 0.92).combined(with: .opacity))
                    }
                }
            }
            .scrollIndicators(.hidden)
            .overlay(alignment: .bottomTrailing) {
                if showsArchive {
                    Button("Clear") { todo.clearArchive() }
                        .buttonStyle(.plain)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
            }
        }
    }

    private func taskRow(_ item: TodoItem) -> some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(NotchMotion.selection) { todo.toggleCompleted(item) }
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(item.isCompleted ? .green : .white.opacity(0.38))
                    .symbolEffect(.bounce, value: item.isCompleted)
            }
            .buttonStyle(.plain)

            Text(item.title)
                .font(.system(size: 11, weight: item.isFavorite ? .semibold : .medium, design: .rounded))
                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                .strikethrough(item.isCompleted, color: .secondary)
                .lineLimit(1)

            Spacer()

            Button {
                todo.toggleFavorite(item)
            } label: {
                Image(systemName: item.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(item.isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isFavorite ? "Remove favourite" : "Favourite")

            Button(role: .destructive) {
                withAnimation(NotchMotion.selection) { todo.delete(item) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete task")
        }
        .padding(.horizontal, 11)
        .frame(height: 34)
        .background(.white.opacity(item.isCompleted ? 0.035 : 0.065), in: RoundedRectangle(cornerRadius: 10))
        .contextMenu {
            Button(item.isCompleted ? "Mark Incomplete" : "Complete") { todo.toggleCompleted(item) }
            Button(item.isFavorite ? "Remove Favourite" : "Favourite") { todo.toggleFavorite(item) }
            Divider()
            Button("Delete", role: .destructive) { todo.delete(item) }
        }
    }

    private func addTask() {
        guard todo.add(title: draft) != nil else { return }
        draft = ""
        isInputFocused = true
    }
}
