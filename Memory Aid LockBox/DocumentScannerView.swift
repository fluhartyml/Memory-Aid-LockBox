//
//  DocumentScannerView.swift
//  Memory Aid LockBox
//
//  Created by Michael Fluharty on 4/16/26.
//

#if os(iOS)
import SwiftUI
import VisionKit

struct DocumentScannerView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    var onScan: ([Data]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss, onScan: onScan)
    }

    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let dismiss: DismissAction
        let onScan: ([Data]) -> Void

        init(dismiss: DismissAction, onScan: @escaping ([Data]) -> Void) {
            self.dismiss = dismiss
            self.onScan = onScan
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            var pages: [Data] = []
            for i in 0..<scan.pageCount {
                let image = scan.imageOfPage(at: i)
                if let data = image.jpegData(compressionQuality: 0.8) {
                    pages.append(data)
                }
            }
            onScan(pages)
            dismiss()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            dismiss()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            dismiss()
        }
    }
}
#endif
