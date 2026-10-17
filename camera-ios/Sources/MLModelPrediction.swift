import Foundation
import CoreML

class Waifu2xInput: NSObject, MLFeatureProvider {
    var input: MLMultiArray

    var featureNames: Set<String> {
        ["input"]
    }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        if featureName == "input" {
            return MLFeatureValue(multiArray: input)
        }
        return nil
    }

    init(_ input: MLMultiArray) {
        self.input = input
        super.init()
    }
}

extension MLModel {

    func prediction(input: MLMultiArray) throws -> MLMultiArray {
        let provider = Waifu2xInput(input)
        let outFeatures = try prediction(from: provider)
        guard let result = outFeatures.featureValue(for: "conv7")?.multiArrayValue else {
            throw NSError(domain: "SRPipeline", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "conv7 output missing"])
        }
        return result
    }
}
