import Foundation
import SwiftData
import SwiftUI

struct CoachView: View {
    private struct Message: Identifiable {
        enum Role { case athlete, coach }

        let id: UUID
        let role: Role
        let text: String
        let evidence: String?

        init(
            id: UUID = UUID(),
            role: Role,
            text: String,
            evidence: String? = nil
        ) {
            self.id = id
            self.role = role
            self.text = text
            self.evidence = evidence
        }
    }

    @Query(sort: \WeeklyPlan.startDate) private var plans: [WeeklyPlan]
    @Query private var profiles: [AthleteProfile]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.healthProvider) private var healthProvider
    @Environment(\.atheviaTheme) private var theme

    @State private var messages: [Message] = []
    @State private var draft = ""
    @State private var preview: CoachPlanChangePreview?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var canUndo = false
    @State private var conversations: [CoachConversation] = []
    @State private var currentConversationID: UUID?
    @State private var showsHistory = false
    @State private var showsAIConsent = false
    @State private var pendingAIRequest: String?
    @AppStorage("athevia.coach.external-ai-consent.v1") private var externalAIConsent = false
    @FocusState private var isComposerFocused: Bool

    private let suggestions = [
        "Analyze my last completed workout.",
        "Create a workout for tomorrow based on my recent training.",
        "Explain why this workout is planned today."
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            if messages.isEmpty {
                                coachWelcome
                                suggestedQuestions
                            } else {
                                conversationHeader
                                ForEach(messages) { message in
                                    messageRow(message)
                                        .id(message.id)
                                }
                            }

                            if let preview {
                                previewCard(preview)
                                    .id("coach-preview")
                            }

                            if isWorking {
                                thinkingRow
                                    .id("coach-working")
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 22)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .contentShape(Rectangle())
                    .onTapGesture { isComposerFocused = false }
                    .onChange(of: messages.count) {
                        if let last = messages.last {
                            withAnimation(.easeOut(duration: 0.22)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: preview?.id) {
                        guard preview != nil else { return }
                        withAnimation(.easeOut(duration: 0.22)) {
                            proxy.scrollTo("coach-preview", anchor: .bottom)
                        }
                    }
                }

                composer
            }
            .atheviaScreen()
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("History") {
                        isComposerFocused = false
                        refreshConversations()
                        showsHistory = true
                    }
                    .accessibilityLabel("Conversation history")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("New") {
                        startNewConversation()
                    }
                    .disabled(isWorking || preview != nil)
                    .accessibilityLabel("New conversation")
                }
            }
            .alert(
                "Coach couldn't complete that",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .atheviaScreen()
        .sheet(isPresented: $showsHistory) {
            conversationHistorySheet
        }
        .confirmationDialog(
            "Use AI Coach?",
            isPresented: $showsAIConsent,
            titleVisibility: .visible
        ) {
            Button("Continue") {
                externalAIConsent = true
                guard let request = pendingAIRequest else { return }
                pendingAIRequest = nil
                Task { await submit(request, appendAthleteMessage: false) }
            }
            Button("Not now", role: .cancel) {
                pendingAIRequest = nil
                appendMessage(
                    role: .coach,
                    text: "AI analysis is still off. Deterministic plan changes remain available without it.",
                    evidence: nil
                )
            }
        } message: {
            Text("AI analysis sends a bounded training context to Athevia's authenticated AI service. GPS routes and free-form workout notes are not included.")
        }
        .onAppear {
            refreshUndoAvailability()
            refreshConversations()
        }
    }

    private var coachWelcome: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Athevia Coach")
                .font(.title2.weight(.bold))
            Text("Ask about your training or adjust your plan.")
                .font(.subheadline)
                .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AtheviaAdaptiveStyle(.background.secondary, gaming: .surface))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AtheviaAdaptiveStyle(.separator.opacity(0.55), gaming: .border), lineWidth: 0.5)
        )
    }

    private var conversationHeader: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Athevia Coach")
                .font(.subheadline.weight(.semibold))
            Text("Uses your current plan and available training evidence")
                .font(.caption)
                .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 2)
    }

    private var suggestedQuestions: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionEyebrow(text: "Try asking")

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 10
            ) {
                ForEach(Array(suggestions.enumerated()), id: \.element) { index, suggestion in
                    Button {
                        Task { await submit(suggestion) }
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(suggestion)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(AtheviaAdaptiveStyle(.background.secondary, gaming: .surface))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(AtheviaAdaptiveStyle(.separator.opacity(0.5), gaming: .border), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)
                }
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ message: Message) -> some View {
        if message.role == .athlete {
            HStack {
                Spacer(minLength: 52)
                Text(message.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .foregroundStyle(theme.color(.onAccent, classic: Color.onActionSurface))
                    .background(
                        theme.color(.accent, classic: Color.actionSurface),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(message.text)
                        .font(.body)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    if let evidence = message.evidence {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "checkmark.shield")
                                .font(.caption2)
                                .padding(.top, 2)
                            Text(evidence)
                                .font(.caption)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AtheviaAdaptiveStyle(.background.secondary, gaming: .surface))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(AtheviaAdaptiveStyle(.separator.opacity(0.4), gaming: .border), lineWidth: 0.5)
                )

                Spacer(minLength: 28)
            }
        }
    }

    private var thinkingRow: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Reviewing your training history and plan…")
                    .font(.subheadline)
                    .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                AtheviaAdaptiveStyle(.background.secondary, gaming: .surface),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            Spacer(minLength: 28)
        }
    }

    private func previewCard(_ preview: CoachPlanChangePreview) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(theme.color(.success, classic: .green).opacity(0.14))
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(theme.color(.success, classic: .green))
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Review plan change")
                        .font(.headline)
                    Text("Validated, but nothing changes until you apply it.")
                        .font(.caption)
                        .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                }
                Spacer(minLength: 0)
            }

            Divider()

            if case let .changeObjective(before, after) = preview.action {
                comparisonRow(
                    title: "Training goal",
                    before: before.displayName,
                    after: after.displayName
                )
            }

            ForEach(preview.changes) { change in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: changeIcon(change.kind))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.color(.accent, classic: .primary))
                            .frame(width: 30, height: 30)
                            .background(
                                theme.color(.accent, classic: .primary).opacity(0.10),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(changeTitle(change))
                                .font(.subheadline.weight(.semibold))
                            Text(changeDelta(change))
                                .font(.caption)
                                .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    HStack(alignment: .center, spacing: 8) {
                        workoutMiniCard("Before", change.before)
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                        workoutMiniCard("After", change.after)
                    }

                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.caption2)
                            .padding(.top, 2)
                        Text(change.reason)
                            .font(.caption)
                    }
                    .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                }
                .padding(.vertical, 2)
            }

            if preview.changes.isEmpty {
                ForEach(preview.reasons, id: \.self) { reason in
                    Text(reason)
                        .font(.subheadline)
                        .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                }
            }

            HStack(spacing: 10) {
                Button("Keep current plan", role: .cancel) {
                    cancelPreview()
                }
                .buttonStyle(SecondaryActionButtonStyle())
                .frame(maxWidth: .infinity)

                Button("Apply change") {
                    Task { await applyPreview() }
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .frame(maxWidth: .infinity)
            }
            .disabled(isWorking)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AtheviaAdaptiveStyle(.background.secondary, gaming: .surface))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(theme.color(.success, classic: .green).opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private func comparisonRow(title: String, before: String, after: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionEyebrow(text: title)
            HStack(spacing: 8) {
                Text(before)
                    .font(.subheadline)
                    .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                Text(after)
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private func changeIcon(_ kind: CoachWorkoutChangeKind) -> String {
        switch kind {
        case .moved: "calendar.badge.clock"
        case .shortened: "clock.arrow.circlepath"
        case .eased: "gauge.with.dots.needle.33percent"
        case .skipped: "calendar.badge.minus"
        case .replanned: "arrow.triangle.2.circlepath"
        }
    }

    private func changeTitle(_ change: CoachWorkoutChange) -> String {
        switch change.kind {
        case .moved: "Move workout"
        case .shortened: "Shorten workout"
        case .eased: "Reduce workout load"
        case .skipped: "Remove workout"
        case .replanned: "Replan workout"
        }
    }

    private func changeDelta(_ change: CoachWorkoutChange) -> String {
        guard let before = change.before else {
            return change.after.map { "Add \($0.title) on \(TrainingFormatter.shortDate($0.date))" }
                ?? "Update this training week"
        }
        guard let after = change.after else {
            return "\(before.title) on \(TrainingFormatter.shortDate(before.date)) → no session"
        }

        var deltas: [String] = []
        if !Calendar.current.isDate(before.date, inSameDayAs: after.date) {
            deltas.append("\(TrainingFormatter.shortDate(before.date)) → \(TrainingFormatter.shortDate(after.date))")
        }
        if before.title != after.title {
            deltas.append("\(before.title) → \(after.title)")
        }

        let beforeDuration = before.estimatedDurationSeconds.map { Int(($0 / 60).rounded()) }
        let afterDuration = after.estimatedDurationSeconds.map { Int(($0 / 60).rounded()) }
        if beforeDuration != afterDuration, let beforeDuration, let afterDuration {
            deltas.append("\(beforeDuration) min → \(afterDuration) min")
        }

        let beforeDistance = before.estimatedDistanceMeters
        let afterDistance = after.estimatedDistanceMeters
        if beforeDistance != afterDistance, let beforeDistance, let afterDistance {
            deltas.append("\(formatDistance(beforeDistance)) → \(formatDistance(afterDistance))")
        }

        if before.targetRPE != after.targetRPE {
            switch (before.targetRPE, after.targetRPE) {
            case let (beforeRPE?, afterRPE?):
                deltas.append("Effort \(TrainingFormatter.rpe(beforeRPE)) → \(TrainingFormatter.rpe(afterRPE))")
            case let (beforeRPE?, nil):
                deltas.append("Effort \(TrainingFormatter.rpe(beforeRPE)) → no target")
            case let (nil, afterRPE?):
                deltas.append("Effort target → \(TrainingFormatter.rpe(afterRPE))")
            case (nil, nil):
                break
            }
        }

        return deltas.isEmpty ? "Workout prescription will be updated" : deltas.joined(separator: " · ")
    }

    private func formatDistance(_ meters: Double) -> String {
        meters >= 1_000
            ? String(format: "%.1f km", meters / 1_000)
            : "\(Int(meters.rounded())) m"
    }

    private func workoutMiniCard(
        _ label: String,
        _ workout: CoachWorkoutSnapshot?
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionEyebrow(text: label)

            if let workout {
                HStack(spacing: 7) {
                    DisciplineBadge(discipline: workout.discipline, size: 28)
                    Text(workout.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    Text(TrainingFormatter.shortDate(workout.date))
                    if let seconds = workout.estimatedDurationSeconds {
                        Text("·")
                        Text("\(Int((seconds / 60).rounded())) min")
                    } else if let meters = workout.estimatedDistanceMeters {
                        Text("·")
                        Text(meters >= 1_000
                             ? String(format: "%.1f km", meters / 1_000)
                             : "\(Int(meters.rounded())) m")
                    }
                }
                .font(.caption)
                .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))

                if workout.status == .skipped {
                    Label("Skipped", systemImage: "forward.end")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                }
            } else {
                Text("No session")
                    .font(.subheadline)
                    .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(
            AtheviaAdaptiveStyle(.fill.quaternary, gaming: .raisedSurface),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask about your training…", text: $draft, axis: .vertical)
                    .focused($isComposerFocused)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(
                        AtheviaAdaptiveStyle(.fill.tertiary, gaming: .raisedSurface),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(AtheviaAdaptiveStyle(.separator.opacity(0.45), gaming: .border), lineWidth: 0.5)
                    )
                    .submitLabel(.send)
                    .onSubmit(sendDraft)
                    .disabled(isWorking || preview != nil)

                Button(action: sendDraft) {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .frame(width: 42, height: 42)
                        .foregroundStyle(theme.color(.onAccent, classic: Color.onActionSurface))
                        .background(
                            theme.color(.accent, classic: Color.actionSurface),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(
                    isWorking
                        || preview != nil
                        || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .opacity(
                    isWorking
                        || preview != nil
                        || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? 0.4 : 1
                )
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isComposerFocused = false }
                }
            }

            if preview != nil {
                Text("Review the pending plan change before asking something new.")
                    .font(.caption2)
                    .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                    .padding(.bottom, 8)
            }
        }
        .background(AtheviaAdaptiveStyle(.bar, gaming: .canvas))
    }

    private func sendDraft() {
        let request = draft
        guard !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        draft = ""
        isComposerFocused = false
        Task { await submit(request) }
    }

    private var conversationHistorySheet: some View {
        NavigationStack {
            Group {
                if conversations.isEmpty {
                    ContentUnavailableView(
                        "No conversations yet",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Your Coach conversations will appear here after you start chatting.")
                    )
                } else {
                    List {
                        ForEach(conversations) { conversation in
                            Button {
                                loadConversation(conversation)
                                showsHistory = false
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(conversation.title)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    HStack(spacing: 6) {
                                        Text(conversation.updatedAt, format: .dateTime.month(.abbreviated).day())
                                        Text("·")
                                        Text("\(conversation.messages.count) message\(conversation.messages.count == 1 ? "" : "s")")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                                }
                                .padding(.vertical, 5)
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button("Delete", role: .destructive) {
                                    deleteConversation(conversation)
                                }
                            }
                        }
                    }
                    .atheviaList()
                }
            }
            .atheviaScreen()
            .navigationTitle("Coach history")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showsHistory = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @MainActor
    private func submit(_ rawRequest: String, appendAthleteMessage: Bool = true) async {
        let request = rawRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, !isWorking else { return }
        guard preview == nil else {
            errorMessage = "Apply or cancel the current plan preview before requesting another change."
            return
        }
        guard let profile = profiles.first,
              let setup = profile.setup,
              let plan = plans.currentPlan() else {
            appendMessage(
                role: .coach,
                text: "Finish setup and create a current training week before using Coach.",
                evidence: nil
            )
            return
        }

        if appendAthleteMessage {
            appendMessage(role: .athlete, text: request, evidence: nil)
        }

        isWorking = true
        defer { isWorking = false }

        let loader = AthleteContextLoader(provider: healthProvider)
        guard let context = await loader.load(
            profile: profile,
            plans: plans,
            asOf: .now
        ) else {
            appendMessage(
                role: .coach,
                text: "I couldn't build a training context from the current profile.",
                evidence: nil
            )
            return
        }

        let interpretation = await DeterministicCoachIntentInterpreter().interpret(
            request: request,
            context: context,
            plan: plan,
            now: .now
        )

        switch interpretation {
        case .clarification(let question):
            appendMessage(role: .coach, text: question, evidence: nil)

        case .intent(let intent):
            handleDeterministicIntent(
                intent,
                request: request,
                context: context,
                setup: setup,
                plan: plan
            )

        case .unsupported:
            guard externalAIConsent else {
                pendingAIRequest = request
                showsAIConsent = true
                return
            }

            do {
                let recent = currentStoredConversation?.messages ?? []
                let remote = try await CoachLLMService().respond(
                    request: request,
                    context: context,
                    currentPlan: plan,
                    plans: plans,
                    recentMessages: recent
                )

                switch remote.kind {
                case .analysis:
                    appendMessage(
                        role: .coach,
                        text: remote.message,
                        evidence: remote.evidence.isEmpty ? nil : remote.evidence.joined(separator: " · ")
                    )

                case .workoutProposal:
                    guard let proposal = remote.workout else {
                        appendMessage(
                            role: .coach,
                            text: "I couldn't validate that generated workout. Your plan was not changed.",
                            evidence: nil
                        )
                        return
                    }
                    let response = CoachHybridRouting().workoutPreview(
                        proposal: proposal,
                        request: request,
                        context: context,
                        setup: setup,
                        plan: plan,
                        asOf: .now
                    )
                    let combinedMessage = remote.message.isEmpty
                        ? response.message
                        : remote.message + "\n\n" + response.message
                    appendMessage(
                        role: .coach,
                        text: combinedMessage,
                        evidence: remote.evidence.isEmpty
                            ? response.evidenceSummary
                            : remote.evidence.joined(separator: " · ")
                    )
                    preview = response.preview

                case .deterministicIntent:
                    guard let remoteIntent = remote.intent,
                          let intent = CoachHybridRouting().intent(from: remoteIntent, plan: plan) else {
                        appendMessage(
                            role: .coach,
                            text: "I understood this as a plan update, but I couldn't resolve it safely enough to propose a change.",
                            evidence: nil
                        )
                        return
                    }
                    handleDeterministicIntent(
                        intent,
                        request: request,
                        context: context,
                        setup: setup,
                        plan: plan
                    )
                }
            } catch let error as CoachLLMError {
                switch error {
                case .rejected(let message):
                    appendMessage(
                        role: .coach,
                        text: message,
                        evidence: nil
                    )
                case .invalidResponse:
                    appendMessage(
                        role: .coach,
                        text: "I couldn't safely use that AI response. Your training data and plan were not changed.",
                        evidence: nil
                    )
                case .unavailable:
                    appendMessage(
                        role: .coach,
                        text: "AI analysis is unavailable right now. Routine plan changes still work through Athevia's deterministic engine.",
                        evidence: nil
                    )
                }
            } catch {
                appendMessage(
                    role: .coach,
                    text: "AI analysis is unavailable right now. Routine plan changes still work through Athevia's deterministic engine.",
                    evidence: nil
                )
            }
        }
    }

    @MainActor
    private func handleDeterministicIntent(
        _ intent: CoachIntent,
        request: String,
        context: AthleteContextSnapshot,
        setup: AthleteSetup,
        plan: WeeklyPlan
    ) {
        let response = CoachDomainEngine().respond(
            to: intent,
            originalRequest: request,
            context: context,
            setup: setup,
            currentPlan: plan,
            plans: plans,
            asOf: .now
        )
        appendMessage(
            role: .coach,
            text: response.message,
            evidence: response.evidenceSummary
        )
        preview = response.preview
    }

    @MainActor
    private func applyPreview() async {
        guard !isWorking,
              let pending = preview,
              let profile = profiles.first,
              let plan = plans.currentPlan() else { return }

        isWorking = true
        defer { isWorking = false }

        let loader = AthleteContextLoader(provider: healthProvider)
        guard let freshContext = await loader.load(
            profile: profile,
            plans: plans,
            asOf: .now
        ) else {
            errorMessage = "The current training evidence could not be rebuilt."
            return
        }

        do {
            _ = try await CoachActionApplier(context: modelContext).apply(
                pending,
                confirmed: true,
                profile: profile,
                plan: plan,
                currentContext: freshContext,
                asOf: .now
            )
            preview = nil
            appendMessage(
                role: .coach,
                text: "Applied. The current plan and upcoming Watch schedule were reconciled. Completed history was not changed.",
                evidence: nil
            )
            refreshUndoAvailability()
        } catch let error as CoachActionError
            where error == .stalePreview || error == .actionNoLongerMatchesPreview {
            preview = nil
            appendMessage(
                role: .coach,
                text: "Your plan or relevant evidence changed after that preview. I rebuilt the request below; review it again before applying.",
                evidence: nil
            )
            await submit(pending.originalRequest, appendAthleteMessage: false)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "The plan change could not be applied."
        }
    }

    @MainActor
    private func cancelPreview() {
        guard var pending = preview else { return }
        pending.confirmationState = .cancelled
        preview = nil
        appendMessage(
            role: .coach,
            text: "Cancelled. No training data or plan was changed.",
            evidence: nil
        )
    }

    @MainActor
    private func undoLatest() async {
        guard !isWorking,
              let profile = profiles.first,
              let plan = plans.currentPlan() else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            _ = try await CoachActionApplier(context: modelContext)
                .undoLatestEligibleChange(
                    profile: profile,
                    plan: plan,
                    asOf: .now
                )
            appendMessage(
                role: .coach,
                text: "Undone. Only the eligible future-plan portion of the latest Coach change was restored, and Watch scheduling was reconciled again.",
                evidence: nil
            )
            refreshUndoAvailability()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "That Coach change cannot be safely undone."
            refreshUndoAvailability()
        }
    }

    private var conversationStore: CoachConversationStore? {
        guard let profile = profiles.first else { return nil }
        return CoachConversationStore(athleteScopeID: profile.id.uuidString)
    }

    private var currentStoredConversation: CoachConversation? {
        guard let currentConversationID else { return nil }
        return conversations.first { $0.id == currentConversationID }
    }

    @MainActor
    private func refreshConversations() {
        conversations = conversationStore?.conversations() ?? []
    }

    @MainActor
    private func startNewConversation() {
        guard !isWorking, preview == nil else { return }
        currentConversationID = nil
        messages = []
        draft = ""
        errorMessage = nil
        isComposerFocused = true
    }

    @MainActor
    private func loadConversation(_ conversation: CoachConversation) {
        currentConversationID = conversation.id
        messages = conversation.messages.map { stored in
            Message(
                id: stored.id,
                role: stored.role == .athlete ? .athlete : .coach,
                text: stored.text,
                evidence: stored.evidence.isEmpty ? nil : stored.evidence.joined(separator: " · ")
            )
        }
        preview = nil
        draft = ""
        errorMessage = nil
        isComposerFocused = false
    }

    @MainActor
    private func deleteConversation(_ conversation: CoachConversation) {
        conversationStore?.delete(conversation.id)
        if currentConversationID == conversation.id {
            currentConversationID = nil
            messages = []
            preview = nil
        }
        refreshConversations()
    }

    @MainActor
    private func appendMessage(
        role: Message.Role,
        text: String,
        evidence: String?
    ) {
        let message = Message(role: role, text: text, evidence: evidence)
        messages.append(message)
        persistConversation()
    }

    @MainActor
    private func persistConversation() {
        guard let store = conversationStore else { return }
        let now = Date.now

        var conversation: CoachConversation
        if let currentConversationID,
           let stored = conversations.first(where: { $0.id == currentConversationID }) {
            conversation = stored
        } else {
            conversation = CoachConversation(createdAt: now, updatedAt: now)
            currentConversationID = conversation.id
        }

        conversation.messages = messages.map { message in
            CoachChatMessage(
                id: message.id,
                role: message.role == .athlete ? .athlete : .coach,
                text: message.text,
                evidence: message.evidence.map { [$0] } ?? [],
                createdAt: now
            )
        }
        if let firstRequest = conversation.messages.first(where: { $0.role == .athlete })?.text {
            conversation.title = CoachConversationTitle.from(firstRequest: firstRequest)
        }
        conversation.updatedAt = now
        store.saveConversation(conversation)
        refreshConversations()
    }

    @MainActor
    private func refreshUndoAvailability() {
        guard let profile = profiles.first,
              let plan = plans.currentPlan() else {
            canUndo = false
            return
        }
        canUndo = CoachActionJournal(athleteScopeID: profile.id.uuidString)
            .latestUndoable(planID: plan.id) != nil
    }

}
