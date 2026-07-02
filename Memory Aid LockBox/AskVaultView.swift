//
//  AskVaultView.swift
//  Memory Aid LockBox
//
//  "Ask your vault" — a plain-language question box that answers from the user's
//  own entries, entirely on-device (see AskVaultService). Presented only while
//  the vault is unlocked.
//

import SwiftUI
import SwiftData

struct AskVaultView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var items: [VaultItem]

    @State private var question = ""
    @State private var result: AskVaultService.Result?
    @State private var isThinking = false

    /// Called when the user taps a source entry — the caller opens that item.
    var onOpenItem: (VaultItem) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    questionField
                    if let result {
                        answerCard(result)
                    } else {
                        hint
                    }
                }
                .padding()
            }
            .navigationTitle("Ask Your Vault")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Question field

    private var questionField: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("Ask about anything you've saved…", text: $question, axis: .vertical)
                    .font(.system(size: 18))
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    #if os(iOS)
                    .submitLabel(.search)
                    #endif
                    .onSubmit(ask)
                if isThinking {
                    ProgressView()
                }
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button(action: ask) {
                Label("Ask", systemImage: "sparkle.magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isThinking)
        }
    }

    // MARK: - Answer

    private func answerCard(_ result: AskVaultService.Result) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(result.answer)
                .font(.system(size: 18))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if !result.sources.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("From these entries")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ForEach(result.sources) { item in
                        Button {
                            onOpenItem(item)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "doc.text")
                                    .foregroundStyle(.secondary)
                                Text(item.title.isEmpty ? "Untitled" : item.title)
                                    .font(.system(size: 16))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Label(result.usedModel
                  ? "Answered on your device — nothing left it."
                  : "Matched by keyword on your device (the smart answer needs an Apple Intelligence device).",
                  systemImage: "lock.shield")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private var hint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask in your own words")
                .font(.system(size: 16, weight: .semibold))
            Text("For example: \"what's mom's Netflix password\", \"where did I park\", or \"the vet's phone number\". Answers are drawn only from what you've saved, and never leave this device.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    // MARK: - Action

    private func ask() {
        let q = question
        guard !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task {
            isThinking = true
            let answer = await AskVaultService.answer(question: q, items: items)
            result = answer
            isThinking = false
        }
    }
}
