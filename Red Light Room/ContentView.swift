//
//  ContentView.swift
//  Red Light Room
//
//  Created by Aleksandr Vinokurov on 02-04-2024.
//

import SwiftUI
import Photos
import CloudKit

struct ContentView: View {

    var body: some View {
        VStack {
            Image(systemName: "archivebox.fill")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Button("Backup and Delete Photos") {
                backupAndDeletePhotos()
            }
        }
        .padding()
    }

    let group = DispatchGroup()
    let semaphore = DispatchSemaphore(value: 10)

    func backupAndDeletePhotos() {
        let allPhotos = PHAsset.fetchAssets(with: .image, options: nil)
        print("\(allPhotos.count) assets found")

        var budget = 100

        allPhotos.enumerateObjects { (asset, _, _) in
            
            guard budget > 0 else {
//                print("Budget depleted. Cannot perform operation.")
                return
            }

            // Wait for the group to be empty (i.e., wait for the task to complete)
            group.wait()

            handle(the: asset)
            budget -= 1
        }
        print("Done")
    }

    func checkIfFileExists(at serverURL: URL, completion: @escaping (Bool) -> Void) {

        DispatchQueue.global(qos: .background).async {
            self.semaphore.wait() // Wait to acquire a "slot"

            var request = URLRequest(url: serverURL)
            request.httpMethod = "HEAD"

            semaphore.wait() // Wait to acquire a "slot"
            group.enter()

            let task = URLSession.shared.dataTask(with: request) { _, response, error in
                defer {
                    self.semaphore.signal() // Release the "slot"
//                    group.leave()
                }

                guard error == nil else {
                    DispatchQueue.main.async {
                        print("Error checking file: \(error!.localizedDescription)")
                        completion(false)
                    }
                    return
                }

                let fileExists = (response as? HTTPURLResponse)?.statusCode == 200
                DispatchQueue.main.async {
                    completion(fileExists)
                }
            }

            task.resume()
        }
    }

    enum MyError: Error {
        case runtimeError(String)
    }

    func uploadFile(_ imageData: Data, at path: String) {
        //guard let imageData = image.jpegData(compressionQuality: 0.5) else { return }
        let uploadURL = URL(string: "http://Aleksandrs-MacBook-Air.local:8080/\(path.replacingOccurrences(of: "/", with: "_"))")!

        var request = URLRequest(url: uploadURL)

        if path.lowercased().hasSuffix(".heic") {
            request.setValue("image/heic", forHTTPHeaderField: "Content-Type")
        } else if path.lowercased().hasSuffix(".jpg") {
            request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        } else if path.lowercased().hasSuffix(".png") {
            request.setValue("image/png", forHTTPHeaderField: "Content-Type")
        } else {
            print("Unsupported suffix")
            return
        }

        // Move checking and upload task to background thread
        DispatchQueue.global(qos: .background).async {
            self.checkIfFileExists(at: uploadURL) { exists in
                guard !exists else {
                    print("File already exists at \(uploadURL)")
                    return
                }

                var request = URLRequest(url: uploadURL)
                request.httpMethod = "PUT"
                request.httpBody = imageData

                semaphore.wait() // Wait to acquire a "slot"
                group.enter()

                let task = URLSession.shared.uploadTask(with: request, from: imageData) { data, response, error in
                    defer {
                        semaphore.signal() // Release the "slot"
                        group.leave()
                    }

                    DispatchQueue.main.async {
                        if let error = error {
                            print("Upload error: \(error)")
                            return
                        }
                        guard let response = response as? HTTPURLResponse,
                              (200...299).contains(response.statusCode) else {
                            print("Server error")
                            return
                        }
                        print("Upload successful")
                    }
                }
                task.resume()
            }
        }
    }

    func handle(the asset: PHAsset) {
        let fileName = PHAssetResource.assetResources(for: asset)[0].originalFilename
        print("\(asset.localIdentifier) : \(fileName) - \(asset.creationDate?.description ?? "unknown")")
        // For each photo, request the image data
        PHImageManager.default().requestImageData(for: asset, options: nil) { (data, _, _, _) in
            guard let data = data else { return }

            uploadFile(data, at: fileName)

            // Optionally, delete the photo after backing it up
//            PHPhotoLibrary.shared().performChanges({
//                PHAssetChangeRequest.deleteAssets([asset] as NSArray)
//            })
        }
    }
}

#Preview {
    ContentView()
}
