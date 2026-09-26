import SwiftUI
import UIKit

/// A single selectable answer.
///
/// Built on the existing `Card` language rather than a new one: same corner
/// radius, same separator border, with selection carried by the accent tint.
struct OptionCard: View {
    let title: String
    var detail: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .multilineTextAlignment(.leading)
                    if let detail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(.background.secondary))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Title and supporting line at the top of an onboarding step.
struct OnboardingHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Optional lesser action under the primary button.
///
/// A named type rather than a tuple: an optional labelled tuple behind a
/// ternary defeats type inference badly enough that the compiler gives up
/// without a diagnostic.
struct OnboardingSecondaryAction {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }
}

/// Scrolling body with a pinned primary action, shared by every step so the
/// call to action never moves between screens.
struct OnboardingStep<Content: View>: View {
    var primaryTitle: String = "Continue"
    var isPrimaryEnabled: Bool = true
    var secondary: OnboardingSecondaryAction?
    let primary: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(KeyboardDismissOnBackgroundTap())
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button(primaryTitle, action: primary)
                    .buttonStyle(PrimaryActionButtonStyle())
                    .disabled(!isPrimaryEnabled)

                if let secondary {
                    Button(secondary.title, action: secondary.action)
                        .font(.subheadline)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(.bar)
        }
    }
}


/// Dismisses the keyboard when the athlete taps outside an editable control.
/// The recognizer never cancels the underlying SwiftUI tap, and deliberately
/// ignores text inputs so focusing a field does not immediately dismiss it.
private struct KeyboardDismissOnBackgroundTap: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        DispatchQueue.main.async {
            guard let host = view.window else { return }
            let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.dismissKeyboard))
            tap.cancelsTouchesInView = false
            tap.delegate = context.coordinator
            host.addGestureRecognizer(tap)
            context.coordinator.gesture = tap
            context.coordinator.host = host
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        if let gesture = coordinator.gesture {
            coordinator.host?.removeGestureRecognizer(gesture)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var gesture: UITapGestureRecognizer?
        weak var host: UIView?

        @objc func dismissKeyboard() {
            host?.endEditing(true)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view: UIView? = touch.view
            while let current = view {
                if current is UITextField || current is UITextView { return false }
                view = current.superview
            }
            return true
        }
    }
}
