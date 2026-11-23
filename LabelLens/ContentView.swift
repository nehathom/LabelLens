import SwiftUI
import PhotosUI

struct ContentView: View {
    @State private var image: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false

    @State private var avoidListText = "peanut, milk, wheat, soy"
    @State private var recognizedLines: [String] = []
    @State private var result: ValidatedReport?
    @State private var errorMessage: String?
    @State private var isWorking = false

    private let recognizer = TextRecognizer()
    private let analyzer = LabelAnalyzer()

    var body: some View {
        NavigationStack {
            Form {
                Section("Avoid list (comma separated)") {
                    TextField("e.g. peanut, milk", text: $avoidListText)
                        .textInputAutocapitalization(.never)
                }

                Section("Label") {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 240)
                    }
                    HStack {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button("Take Photo") { showCamera = true }
                        }
                        Spacer()
                        PhotosPicker("Choose Photo", selection: $pickerItem, matching: .images)
                    }
                    .buttonStyle(.borderless)
                }

                if isWorking {
                    Section { ProgressView("Analyzing on device…") }
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }

                if let result {
                    resultSection(result)
                }

                if !recognizedLines.isEmpty {
                    Section("Recognized text (Vision OCR)") {
                        Text(recognizedLines.joined(separator: "\n"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("LabelLens")
            .sheet(isPresented: $showCamera) {
                CameraPicker { process($0) }
                    .ignoresSafeArea()
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let picked = UIImage(data: data) {
                        process(picked)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func resultSection(_ validated: ValidatedReport) -> some View {
        let report = validated.report
        Section("Result") {
            LabeledContent("Product", value: report.productName)
            Text(report.summary)

            if report.flagged.isEmpty {
                Label("Nothing from your avoid list", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            } else {
                Label("Contains: \(report.flagged.joined(separator: ", "))",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            DisclosureGroup("Ingredients (\(report.ingredients.count))") {
                ForEach(report.ingredients, id: \.self) { Text($0) }
            }

            ForEach(validated.validationNotes, id: \.self) { note in
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func process(_ newImage: UIImage) {
        image = newImage
        result = nil
        errorMessage = nil
        recognizedLines = []
        isWorking = true

        let avoidList = avoidListText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }

        Task {
            defer { isWorking = false }
            do {
                recognizedLines = try recognizer.recognize(in: newImage)
                result = try await analyzer.analyze(lines: recognizedLines, avoidList: avoidList)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    ContentView()
}
