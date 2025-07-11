import SwiftUI

struct StatusErrorView: View {
    let isLoading: Bool
    let statusMessage: String
    let errorMessage: String?
    let parsedDataIsAvailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if isLoading { ProgressView().scaleEffect(0.7) }
                Text(statusMessage).font(.caption).foregroundColor(.secondary).lineLimit(1)
                Spacer()
            }

            if let errorMsg = errorMessage {
                let isNoObjCMetaError = errorMsg.contains("No Objective-C")
                let errorColor: Color = (isNoObjCMetaError && parsedDataIsAvailable) ? .orange : .red
                Text(errorMsg)
                    .font(.caption)
                    .foregroundColor(errorColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal)
    }
}
