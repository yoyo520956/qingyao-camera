import CoreImage
import SwiftUI

struct FilterPreset: Identifiable, Equatable {
    let id: Int
    let name: String
    let accent: Color
    let apply: (CIImage) -> CIImage

    static func == (lhs: FilterPreset, rhs: FilterPreset) -> Bool {
        lhs.id == rhs.id
    }
}

enum FilterLibrary {

    static let presets: [FilterPreset] = [
        FilterPreset(id: 0, name: "原图", accent: Color(white: 0.55)) { image in
            image
        },
        FilterPreset(id: 1, name: "胶片", accent: Color(red: 0.98, green: 0.72, blue: 0.42)) { image in
            apply("CIPhotoEffectTransfer", to: image)
        },
        FilterPreset(id: 2, name: "黑白", accent: Color(white: 0.35)) { image in
            apply("CIPhotoEffectNoir", to: image)
        },
        FilterPreset(id: 3, name: "银盐", accent: Color(white: 0.72)) { image in
            apply("CIColorControls", to: apply("CIPhotoEffectMono", to: image),
                  params: [kCIInputContrastKey: 1.08])
        },
        FilterPreset(id: 4, name: "电影", accent: Color(red: 0.35, green: 0.65, blue: 0.85)) { image in
            apply("CIPhotoEffectProcess", to: image)
        },
        FilterPreset(id: 5, name: "冷冽", accent: Color(red: 0.45, green: 0.78, blue: 1.0)) { image in
            let cooled = apply("CIColorMatrix", to: image, params: [
                "inputRVector": CIVector(x: 0.92, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1.0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1.10, w: 0)
            ])
            return apply("CIColorControls", to: cooled, params: [kCIInputContrastKey: 1.10])
        },
        FilterPreset(id: 6, name: "暖阳", accent: Color(red: 1.0, green: 0.78, blue: 0.45)) { image in
            let warmed = apply("CIColorMatrix", to: image, params: [
                "inputRVector": CIVector(x: 1.10, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1.02, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.92, w: 0)
            ])
            return apply("CIColorControls", to: warmed, params: [kCIInputBrightnessKey: 0.02])
        },
        FilterPreset(id: 7, name: "赛博", accent: Color(red: 0.72, green: 0.42, blue: 1.0)) { image in
            let purple = apply("CIColorMatrix", to: image, params: [
                "inputRVector": CIVector(x: 0.98, y: 0, z: 0.10, w: 0),
                "inputGVector": CIVector(x: 0, y: 0.95, z: 0, w: 0),
                "inputBVector": CIVector(x: 0.08, y: 0, z: 1.12, w: 0)
            ])
            return apply("CIColorControls", to: purple, params: [
                kCIInputSaturationKey: 1.30,
                kCIInputContrastKey: 1.15
            ])
        },
        FilterPreset(id: 8, name: "褪色", accent: Color(red: 0.68, green: 0.68, blue: 0.62)) { image in
            apply("CIPhotoEffectFade", to: image)
        },
        FilterPreset(id: 9, name: "鲜艳", accent: Color(red: 1.0, green: 0.45, blue: 0.55)) { image in
            apply("CIColorControls", to: image, params: [
                kCIInputSaturationKey: 1.42,
                kCIInputContrastKey: 1.06
            ])
        }
    ]

    static func apply(_ name: String, to image: CIImage, params: [String: Any] = [:]) -> CIImage {
        guard let filter = CIFilter(name: name) else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        for (key, value) in params {
            filter.setValue(value, forKey: key)
        }
        return filter.outputImage ?? image
    }
}
