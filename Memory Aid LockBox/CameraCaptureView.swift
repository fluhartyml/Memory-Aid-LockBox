//
//  CameraCaptureView.swift
//  Memory Aid LockBox
//
//  Created by Michael Fluharty on 4/16/26.
//

#if os(iOS)
import SwiftUI
import UIKit

struct CameraCaptureView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    var onCapture: (Data) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss, onCapture: onCapture)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let dismiss: DismissAction
        let onCapture: (Data) -> Void

        init(dismiss: DismissAction, onCapture: @escaping (Data) -> Void) {
            self.dismiss = dismiss
            self.onCapture = onCapture
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWith info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.8) {
                onCapture(data)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
#endif
