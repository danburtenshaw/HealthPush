import SwiftUI

// MARK: - AddDestinationSheet

/// A half-sheet picker for choosing which destination type to add.
///
/// Replaces inline `confirmationDialog` usage with a proper sheet that
/// follows Apple HIG: clear title, descriptive rows, and predictable
/// bottom-sheet presentation on all device sizes.
struct AddDestinationSheet: View {
    // MARK: Properties

    /// Called when the user selects a destination type to add.
    var onSelect: (DestinationType) -> Void

    @Environment(\.dismiss) private var dismiss

    // MARK: Body

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Choose a destination type")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                ForEach(DestinationType.allCases) { type in
                    Button {
                        dismiss()
                        onSelect(type)
                    } label: {
                        destinationRow(for: type)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .navigationTitle("Add Destination")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGroupedBackground))
    }

    // MARK: Subviews

    private func destinationRow(for type: DestinationType) -> some View {
        HStack(spacing: 14) {
            Image(systemName: type.symbolName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(iconColor(for: type), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(type.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(subtitle(for: type))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(type.displayName) setup")
    }

    // MARK: Helpers

    private func subtitle(for type: DestinationType) -> String {
        switch type {
        case .s3:
            "AWS S3 or any S3-compatible bucket"
        case .homeAssistant:
            "Push sensors to your HA instance"
        }
    }

    private func iconColor(for type: DestinationType) -> Color {
        switch type {
        case .s3:
            .orange
        case .homeAssistant:
            .blue
        }
    }
}

// MARK: - Preview

#Preview {
    Text("Background")
        .sheet(isPresented: .constant(true)) {
            AddDestinationSheet { _ in }
        }
}
