//
//  ImageViewerView.swift
//  Memory Aid LockBox
//
//  Created by Michael Fluharty on 4/16/26.
//

#if os(iOS)
import SwiftUI
import UIKit

struct ImageViewerView: View {
    let imageData: Data
    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            if let uiImage = UIImage(data: imageData) {
                GeometryReader { geo in
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = lastScale * value
                                }
                                .onEnded { value in
                                    lastScale = scale
                                    if scale < 1.0 {
                                        withAnimation {
                                            scale = 1.0
                                            lastScale = 1.0
                                            offset = .zero
                                            lastOffset = .zero
                                        }
                                    }
                                }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    if scale > 1.0 {
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation {
                                if scale > 1.0 {
                                    scale = 1.0
                                    lastScale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    scale = 3.0
                                    lastScale = 3.0
                                }
                            }
                        }
                }
                .background(Color.black)
                .ignoresSafeArea()
                .navigationTitle("Scan")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.black, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                            .font(.system(size: 18))
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 18))
                        }
                    }
                }
                .sheet(isPresented: $showShareSheet) {
                    let image = UIImage(data: imageData)!
                    ShareActivityView(items: [image])
                }
            }
        }
    }
}

struct ShareActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
