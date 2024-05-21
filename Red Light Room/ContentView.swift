//
//  ContentView.swift
//  Red Light Room
//
//  Created by Aleksandr Vinokurov on 02-04-2024.
//

import SwiftUI
import Photos
import CloudKit

extension URLSession {
    func synchronousDataTask(with url: URL) -> (Data?, URLResponse?, Error?) {
        return synchronousDataTask(with: URLRequest(url: url))
    }

    func synchronousDataTask(with request: URLRequest) -> (Data?, URLResponse?, Error?) {
        var data: Data?
        var response: URLResponse?
        var error: Error?

        let semaphore = DispatchSemaphore(value: 0)

        let dataTask = self.dataTask(with: request) {
            data = $0
            response = $1
            error = $2

            semaphore.signal()
        }
        dataTask.resume()

        print("Waiting for semaphore")

        _ = semaphore.wait(timeout: .distantFuture)

        print("Semaphore awaited")

        return (data, response, error)
    }

    func synchronousUploadTask(with request: URLRequest, data: Data) -> (Data?, URLResponse?, Error?) {
        var data: Data?
        var response: URLResponse?
        var error: Error?

        let semaphore = DispatchSemaphore(value: 0)

        let dataTask = self.uploadTask(with: request, from: data) {
            data = $0
            response = $1
            error = $2

            if let e = error {
                print("Error synchronousUploadTask: \(error!.localizedDescription)")
            }

            semaphore.signal()
        }
        dataTask.resume()

        print("Waiting for semaphore")

        _ = semaphore.wait(timeout: .distantFuture)

        print("Semaphore awaited")

        return (data, response, error)
    }
}

struct ContentView: View {

    var body: some View {
        VStack {
            Image(systemName: "archivebox.fill")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Button("Backup and Delete Photos") {
                backupAndDeletePhotos()
            }
            Text("\(completed) / \(number)")
        }
        .padding()
    }

    var number = PHAsset.fetchAssets(with: .image, options: nil).count

    @State private var completed = 0

    let s = URLSession.shared

    func backupAndDeletePhotos() {
        let allPhotos = PHAsset.fetchAssets(with: .image, options: nil)
        print("\(allPhotos.count) assets found")

        var budget = 1000

        DispatchQueue.global().async {
            allPhotos.enumerateObjects { (asset, idx, stop) in
                guard budget > 0 else {
                    print("Budget depleted. Cannot perform operation.")
                    stop.pointee = true
                    return
                }

                handle(the: asset)

                DispatchQueue.main.async {
                    self.completed += 1
                }

                budget -= 1
            }
        }

        //handle(the: allPhotos.firstObject!)

        print("Done")
    }

    func checkIfFileExists(at serverURL: URL) -> Bool {

        print("checkIfFileExists...")

        var request = URLRequest(url: serverURL)
        request.httpMethod = "HEAD"

        let (_, response, error) = s.synchronousDataTask(with: request)

        guard error == nil else {
            DispatchQueue.main.async {
                print("Error checking file: \(error!.localizedDescription)")
            }
            return false
        }

        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    enum MyError: Error {
        case runtimeError(String)
    }

    func uploadFile(_ imageData: Data, at uploadURL: URL) {
        //guard let imageData = image.jpegData(compressionQuality: 0.5) else { return }

        var request = URLRequest(url: uploadURL)

        if uploadURL.path.lowercased().hasSuffix(".heic") {
            request.setValue("image/heic", forHTTPHeaderField: "Content-Type")
        } else if uploadURL.path.lowercased().hasSuffix(".jpg") {
            request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        } else if uploadURL.path.lowercased().hasSuffix(".png") {
            request.setValue("image/png", forHTTPHeaderField: "Content-Type")
        } else {
            print("Unsupported suffix")
            return
        }
        request.httpMethod = "PUT"
        request.httpBody = imageData

        print("Uploading image...")

        let (_, response, error) = s.synchronousUploadTask(with: request, data: imageData)

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

    func requestImageData(for asset: PHAsset) throws -> (Data?, [AnyHashable : Any]?) {

        var data: Data?
        var error: [AnyHashable : Any]?
        let options = PHImageRequestOptions()
        options.version = .original
        options.isSynchronous = true

        print("Requesting Image Data")

        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) {
            data = $0
            error = $3
            print("requestImageData callback")
        }

        print("requestImageData done")

        return (data, error)
    }

    func handle(the asset: PHAsset) -> Void {
        let fileName = PHAssetResource.assetResources(for: asset)[0].originalFilename
        print("\(asset.localIdentifier) : \(fileName) - \(asset.creationDate?.description ?? "unknown")")
        // For each photo, request the image data

        let uploadURL = URL(string: "http://Aleksandrs-MacBook-Air.local:8080/\(fileName.replacingOccurrences(of: "/", with: "_"))")!

        do {
            if (checkIfFileExists(at: uploadURL)) {
                print("File already exists at \(uploadURL)")
                return
            } else {
                print("File does not exist at \(uploadURL)")
                let (data, error) = try requestImageData(for: asset)
//                if let error = error {
//                    print("requestImageData error: \(error)")
//                    return
//                }
                if let data = data {
                    uploadFile(data, at: uploadURL)
                }

                // Optionally, delete the photo after backing it up
                // Remember to run deletion code on the main thread if affecting the UI
                //            PHPhotoLibrary.shared().performChanges({
                //                PHAssetChangeRequest.deleteAssets([asset] as NSArray)
                //            })
            }
        } catch {
            print("An error occurred: \(error)")
        }
    }
}

#Preview {
    ContentView()
}
