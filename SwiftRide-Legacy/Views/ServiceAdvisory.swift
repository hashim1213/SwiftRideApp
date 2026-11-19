import Foundation
import SwiftUI

struct ServiceAdvisoryListView: View {
    @StateObject var advisoryProvider = ServiceAdvisoryProvider()

    var body: some View {
        List(advisoryProvider.advisories) { advisory in
            VStack(alignment: .leading) {
                Text(advisory.title).font(.headline)
                Text(advisory.body).font(.subheadline)
                Text("Updated: \(advisory.updatedAt.formatted())") // Format the date
            }
        }
        .onAppear {
            advisoryProvider.fetchServiceAdvisories()
        }
        .if(advisoryProvider.advisories.isEmpty) {_ in 
            Text("No Advisories, everything looks good!")
        }
    }
}

extension View {
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
