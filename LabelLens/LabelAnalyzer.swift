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

        let labelText = lines.joined(separator: "\n")
        guard !labelText.isEmpty else { throw AnalyzerError.noText }

        let session = LanguageModelSession(
            tools: [AvoidListTool(avoidList: avoidList)],
            instructions: """
            You read text captured from a product label by OCR. The text may contain OCR errors.
            1. Identify the product and extract the ingredients exactly as they appear on the label.
            2. Always call the checkAvoidList tool with the extracted ingredients.
            3. Put only the tool's matches in `flagged`.
            Do not add ingredients that are not in the text.
            """
        )

        let response = try await session.respond(
            to: "Label text:\n\(labelText)",
            generating: LabelReport.self
        )

        return try validate(response.content, labelText: labelText, avoidList: avoidList)
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
