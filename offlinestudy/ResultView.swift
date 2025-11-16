//
//  ResultView.swift
//  offlinestudy
//
//  Created by Gowri Mohan on 16/11/25.
//

import SwiftUI

struct ResultView: View {
    let image: UIImage
    let result: StudyResult
    
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(10)
                    .shadow(radius: 5)
                
                // --- 1. Your Model's Result ---
                VStack(alignment: .leading) {
                    Text("Page Type")
                        .font(.headline)
                        .foregroundColor(.blue)
                    Text(result.pageType)
                        .font(.title2.bold())
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                
                // --- 2. The Math Result ---
                if let equation = result.mathEquation, let solution = result.mathSolution {
                    VStack(alignment: .leading) {
                        Text("Math Solution")
                            .font(.headline)
                            .foregroundColor(.blue)
                        Text(equation)
                            .font(.title2.bold())
                        Text("= \(solution)")
                            .font(.title.bold())
                            .foregroundColor(.green)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                }
                
                // --- 2. The Summary (if it's a Text page) ---
                if let summary = result.summary, !summary.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Summary")
                            .font(.headline)
                            .foregroundColor(.orange)
                        Text(summary)
                            .font(.body)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                }
                
                // --- 3. The Full OCR'd Text ---
                VStack(alignment: .leading) {
                    Text("Full Text")
                        .font(.caption.bold())
                    Text(result.fullText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle("Analysis Result")
        .navigationBarItems(trailing: Button("Done") {
            presentationMode.wrappedValue.dismiss()
        })
    }
}
