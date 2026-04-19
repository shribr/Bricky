import SwiftUI

/// Button that locates a required piece in the user's last scan photo.
/// Presented inline during build instructions to help find specific pieces in the pile.
struct PieceFinderButton: View {
    let requiredPiece: RequiredPiece
    let scanImage: UIImage?
    @State private var showingFinder = false
    @State private var locations: [PieceLocationService.PieceLocation] = []
    @State private var isSearching = false

    var body: some View {
        Button {
            findPiece()
        } label: {
            HStack(spacing: 4) {
                if isSearching {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.caption2)
                }
                Text("Find in pile")
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.legoGreen.opacity(0.15))
            )
            .foregroundStyle(Color.legoGreen)
        }
        .disabled(scanImage == nil || isSearching)
        .accessibilityLabel("Find \(requiredPiece.displayName) in your pile")
        .sheet(isPresented: $showingFinder) {
            if let image = scanImage {
                PieceLocationOverlayView(
                    image: image,
                    locations: locations,
                    pieceName: requiredPiece.displayName
                )
            }
        }
    }

    private func findPiece() {
        guard let image = scanImage else { return }
        isSearching = true

        DispatchQueue.global(qos: .userInitiated).async {
            let service = PieceLocationService()
            let found = service.locatePieces(
                matching: requiredPiece.colorPreference ?? .gray,
                targetDimensions: requiredPiece.dimensions,
                in: image
            )

            DispatchQueue.main.async {
                locations = found
                isSearching = false
                showingFinder = true
            }
        }
    }
}
