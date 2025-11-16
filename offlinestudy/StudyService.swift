import Foundation
import Vision
import NaturalLanguage
import UIKit
import CoreML

// This struct will hold all our results
struct StudyResult {
    let fullText: String
    var pageType: String = "Unknown" // "Math" or "Text"
    var summary: String?
    var mathEquation: String?
    var mathSolution: String?
}

class StudyService {
    
    static let shared = StudyService()
    
    // 1. Load your custom Core ML model (classfiermodel)
    private let model: classfiermodel? = {
        do {
            return try classfiermodel(configuration: .init())
        } catch {
            print("Failed to load Core ML model: \(error)")
            return nil
        }
    }()
    
    // MARK: - Main Recognition Function
    
    func analyze(image: UIImage, completion: @escaping (StudyResult?) -> Void) {
        guard let cgImage = image.cgImage else { completion(nil); return }
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage)
        let request = VNRecognizeTextRequest { (request, error) in
            guard let observations = request.results as? [VNRecognizedTextObservation], error == nil else {
                completion(nil)
                return
            }
            let fullText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            
            // --- 1. Run Math Solver ---
            let (equation, solution) = self.findAndSolveMath(from: fullText)
            
            // --- 2. Run Classifier ---
            self.classifyPage(image: image) { pageType in
                let finalPageType = pageType ?? "Unknown"
                
                var summary: String?
                // --- 3. If it's a text page, summarize it ---
                if finalPageType == "Text" {
                    summary = self.summarize(text: fullText)
                }
                
                // --- Return all results ---
                let result = StudyResult(fullText: fullText, pageType: finalPageType, summary: summary, mathEquation: equation, mathSolution: solution)
                
                // Final result must be set on the main thread
                DispatchQueue.main.async {
                    completion(result)
                }
            }
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try requestHandler.perform([request])
            } catch {
                completion(nil)
            }
        }
    }
    
    // MARK: - MATH SOLVER (Robust Offline Arithmetic)
    
    private func findAndSolveMath(from text: String) -> (String?, String?) {
        // Broad regex to find a block containing numbers, operations, and parentheses.
        let pattern = "([\\d\\.\\s\\+\\-\\*\\/\\(\\)]+)"
        
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let nsText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            
            for match in matches {
                var expressionString = nsText.substring(with: match.range)
                
                // CRITICAL CLEANUP: Convert OCR symbols and remove invalid characters
                expressionString = expressionString.replacingOccurrences(of: "—", with: "/")
                expressionString = expressionString.replacingOccurrences(of: "÷", with: "/")
                expressionString = expressionString.replacingOccurrences(of: "×", with: "*")
                
                // FIX 1: Isolate the solvable expression (remove newlines/equals signs)
                expressionString = expressionString.replacingOccurrences(of: "\n", with: "")
                expressionString = expressionString.components(separatedBy: "=").first ?? expressionString
                expressionString = expressionString.filter { CharacterSet(charactersIn: "0123456789.+-*/()").contains($0.unicodeScalars.first!) }

                // FINAL VALIDATION: Skip if the string is empty or just contains parentheses/periods after cleanup
                if expressionString.isEmpty || expressionString.rangeOfCharacter(from: .decimalDigits) == nil {
                    continue
                }

                // ADVANCED CHECK: Detect Variables and Algebra (Novelty)
                if expressionString.contains("x") || expressionString.contains("y") {
                    return (expressionString, "Symbolic Evaluation Required.")
                }
                
                // Try solving the entire captured block
                let expression = NSExpression(format: expressionString)
                if let solution = expression.expressionValue(with: nil, context: nil) as? NSNumber {
                    return (expressionString, solution.stringValue)
                }
            }
        } catch {
            print("Math regex failed: \(error.localizedDescription)")
        }
        return (nil, nil)
    }
    
    // MARK: - CLASSIFICATION
    
    private func classifyPage(image: UIImage, completion: @escaping (String?) -> Void) {
        guard let model = self.model else { completion(nil); return }
        guard let pixelBuffer = image.cvPixelBuffer() else { completion(nil); return }
        do {
            let prediction = try model.prediction(image: pixelBuffer)
            completion(prediction.target)
        } catch {
            print("Classification failed: \(error)")
            completion(nil)
        }
    }

    // MARK: - SUMMARIZER (Final Version)
    
    private func summarize(text: String, sentenceCount: Int = 3) -> String {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        
        // FIX: Trim whitespace/newlines immediately after tokenizing
        let sentences = tokenizer.tokens(for: text.startIndex..<text.endIndex)
                                .map { String(text[$0]).trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty } // Remove empty strings
        
        guard sentences.count > sentenceCount else {
            return "" // Return empty string if too short
        }

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        
        // 1. Calculate Scores (Content Score + Position Score)
        let scores = sentences.enumerated().map { (index, sentence) -> (String, Double) in
            tagger.string = sentence
            var contentScore = 0
            
            // Score based on content (Nouns, Verbs, Adjectives)
            tagger.enumerateTags(in: sentence.startIndex..<sentence.endIndex, unit: .word, scheme: .lexicalClass, options: [.omitPunctuation, .omitWhitespace]) { tag, tokenRange in
                if tag == .noun || tag == .verb || tag == .adjective { contentScore += 1 }
                return true
            }
            
            // Score based on position (Novelty: First sentence gets a bonus)
            var positionBonus: Double = 0
            if index == 0 {
                positionBonus = 1.0
            } else if index == sentences.count - 1 {
                positionBonus = 0.5
            }
            
            let finalScore = Double(contentScore) + positionBonus
            return (sentence, finalScore)
        }
        
        // 2. Find top sentences and sort them by original order
        let topSentences = scores.sorted { $0.1 > $1.1 }
                                .prefix(sentenceCount)
                                .sorted { (s1, s2) -> Bool in
                                    // Re-sort using original text ranges
                                    let s1Range = text.range(of: s1.0)
                                    let s2Range = text.range(of: s2.0)
                                    return s1Range?.lowerBound ?? text.startIndex < s2Range?.lowerBound ?? text.startIndex
                                }
                                .map { $0.0 }
        
        return topSentences.joined(separator: " ")
    }
}
