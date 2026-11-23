import Foundation
import FoundationModels

// MARK: - Structured output the model must produce

@Generable
struct LabelReport {
    @Guide(description: "What the product appears to be, in a few words")
    var productName: String

    @Guide(description: "Ingredients listed on the label, lowercase, one per item")
    var ingredients: [String]

    @Guide(description: "Ingredients that matched the user's avoid list, taken from the checkAvoidList tool result")
    var flagged: [String]

    @Guide(description: "One or two plain-language sentences summarizing the label for the user")
    var summary: String
}

// MARK: - Tool the model can call

/// The model extracts ingredients, then calls this tool. Matching is deterministic code, not the model.
struct AvoidListTool: Tool {
    let name = "checkAvoidList"
    let description = "Checks a list of ingredients against the user's avoid list and returns any matches."

    let avoidList: [String]

    @Generable
    struct Arguments {
        @Guide(description: "Ingredients to check, lowercase")
        var ingredients: [String]
    }

    func call(arguments: Arguments) async throws -> String {
        let matches = AvoidListTool.matches(arguments.ingredients, avoidList: avoidList)
        return matches.isEmpty ? "No matches." : "Matches: " + matches.joined(separator: ", ")
    }

    static func matches(_ ingredients: [String], avoidList: [String]) -> [String] {
        ingredients.filter { ingredient in
            avoidList.contains { ingredient.localizedCaseInsensitiveContains($0) }
        }
    }
}

// MARK: - Validated result shown in the UI

struct ValidatedReport {
    var report: LabelReport
    /// Notes about corrections made during validation (shown to the user).
    var validationNotes: [String]
}

enum AnalyzerError: LocalizedError {
    case modelUnavailable(String)
    case noText
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let reason): "On-device model unavailable: \(reason)"
        case .noText: "No text found in the image. Try a clearer photo."
        case .emptyResult: "The model returned no ingredients. Try a photo of the ingredient list."
        }
    }
}

// MARK: - Analyzer

struct LabelAnalyzer {
    func analyze(lines: [String], avoidList: [String]) async throws -> ValidatedReport {
        let model = SystemLanguageModel.default
        if case .unavailable(let reason) = model.availability {
            throw AnalyzerError.modelUnavailable(String(describing: reason))
        }

        let labelText = Self.relevantText(from: lines)
        guard !labelText.isEmpty else { throw AnalyzerError.noText }

        // The on-device model has a small context window. Start with a capped
        // amount of text and retry with less if it still overflows.
        var limit = 1200
        while true {
            do {
                let report = try await runModel(text: String(labelText.prefix(limit)), avoidList: avoidList)
                return try validate(report, labelText: labelText, avoidList: avoidList)
            } catch let error as LanguageModelSession.GenerationError {
                if case .exceededContextWindowSize = error, limit > 300 {
                    limit /= 2
                    continue
                }
                throw error
            }
        }
    }

    private func runModel(text: String, avoidList: [String]) async throws -> LabelReport {
        // A fresh session per attempt so earlier attempts don't use up context.
        let session = LanguageModelSession(
            tools: [AvoidListTool(avoidList: avoidList)],
            instructions: """
            Extract the product name and ingredients from OCR text of a product label. \
            Call checkAvoidList once with the ingredients. Put only its matches in flagged. \
            Never invent ingredients.
            """
        )
        let response = try await session.respond(
            to: "Label text:\n\(text)",
            generating: LabelReport.self
        )
        return response.content
    }

    /// Keep the first few lines (product name) plus everything from "ingredients" onward,
    /// dropping nutrition-table noise that wastes the model's context.
    static func relevantText(from lines: [String]) -> String {
        if let start = lines.firstIndex(where: { $0.localizedCaseInsensitiveContains("ingredient") }) {
            let header = lines.prefix(min(3, start))
            return (header + lines[start...]).joined(separator: "\n")
        }
        return lines.joined(separator: "\n")
    }

    /// Never trust model output blindly: ground it in the OCR text and recompute flags in code.
    private func validate(_ report: LabelReport, labelText: String, avoidList: [String]) throws -> ValidatedReport {
        var notes: [String] = []
        var cleaned = report

        // 1. Grounding: drop ingredients that don't appear in the OCR text (hallucination check).
        let grounded = report.ingredients.filter { labelText.localizedCaseInsensitiveContains($0) }
        let dropped = report.ingredients.count - grounded.count
        if dropped > 0 {
            notes.append("Removed \(dropped) ingredient(s) not found in the label text.")
        }
        cleaned.ingredients = grounded
        guard !grounded.isEmpty else { throw AnalyzerError.emptyResult }

        // 2. Recompute flags deterministically and compare with what the model reported.
        let expected = AvoidListTool.matches(grounded, avoidList: avoidList)
        if Set(expected) != Set(report.flagged) {
            notes.append("Corrected flagged ingredients to match the avoid-list check.")
        }
        cleaned.flagged = expected

        return ValidatedReport(report: cleaned, validationNotes: notes)
    }
}
