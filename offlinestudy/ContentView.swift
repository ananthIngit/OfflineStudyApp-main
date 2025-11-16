import SwiftUI

// This struct will hold our final data
struct ScannedPage: Identifiable {
    let id = UUID()
    let image: UIImage
    let result: StudyResult
}

struct ContentView: View {
    @State private var isShowingScanner = false
    @State private var scannedPage: ScannedPage? = nil
    
    var body: some View {
        NavigationView {
            VStack {
                if let page = scannedPage {
                    ResultView(image: page.image, result: page.result)
                } else {
                    Button("Scan Document") {
                        self.isShowingScanner = true
                    }
                    .font(.title)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
            .navigationTitle("OfflineStudy")
            .sheet(isPresented: $isShowingScanner) {
                ScannerView(scannedPage: $scannedPage, isPresented: $isShowingScanner)
            }
        }
    }
}
