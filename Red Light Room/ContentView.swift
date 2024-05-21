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

//        print("Waiting for semaphore")

        _ = semaphore.wait(timeout: .distantFuture)

//        print("Semaphore awaited")

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

            if error != nil {
                print("Error synchronousUploadTask: \(error!.localizedDescription)")
            }

            semaphore.signal()
        }
        dataTask.resume()

//        print("Waiting for semaphore")

        _ = semaphore.wait(timeout: .distantFuture)

//        print("Semaphore awaited")

        return (data, response, error)
    }
}

struct ContentView: View {

    var body: some View {
        VStack {
            Spacer()
            VStack {
                if let inputImage = img {
                    Image(uiImage: inputImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Image(uiImage: UIImage(named: "img-placeholder")!)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }.frame(height: 200, alignment: .center)
                    .cornerRadius(10)
//                    .background(Color.blue)
                    .padding(5)
//                    .border(Color.blue, width: 5)
                    .cornerRadius(10)
            Spacer()
            Slider(value: $oneRunBudget, in: 0...500, step: 1)
                .disabled(inAction)
                .padding()
            Image(systemName: "archivebox.fill")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Button("Backup and Delete \(Int(oneRunBudget)) Photos") {
                backupAndDeletePhotos()
            }.padding()
                .disabled(inAction)
            Spacer()
            if let completed = completed {
                let value = Double(completed)
                let total = Double(Int(oneRunBudget))
                ProgressView(value: value, total: total) {
                    Text("\(completed) / \(Int(oneRunBudget))")
                }
            } else {
                Text("\(allPhotos.count)")
            }
            if let operationsPerMinute = operationsPerMinute {
                Text("ETA: \(eta) min (\(operationsPerMinute) op/min)").foregroundColor(.secondary)
            }
            if (retries > 0) {
                Text("Retries: \(retries)").foregroundColor(.secondary)
            }
        }
        .padding()
    }

    @State private var progress: Double? = nil

    @State private var allPhotos = PHAsset.fetchAssets(with: .image, options: nil)

    @State private var completed: Int?

    @State private var img: UIImage? = nil

    @State private var retries = 0

    @State private var operationsPerMinute: Double?
    @State private var eta: Double = 0.0

    @State private var startTime: Date = Date()

    @State private var oneRunBudget: Double = 3.0

    @State private var inAction: Bool = false

    @State private var forDeletion: [PHAsset] = Array()

    let s = URLSession.shared

    func requestPhotoLibraryAccess(completion: @escaping (Bool) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus()
        switch status {
        case .authorized, .limited:
            completion(true)
        case .denied, .restricted:
            completion(false)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization { newStatus in
                completion(newStatus == .authorized || newStatus == .limited)
            }
        @unknown default:
            completion(false)
        }
    }

    func backupAndDeletePhotos() {
        requestPhotoLibraryAccess { granted in
            guard granted else {
                print("Access to photo library denied.")
                return
            }
            let allPhotos = PHAsset.fetchAssets(with: .image, options: nil)
            let number = allPhotos.count
            print("\(number) assets found")

            startTime = Date()

            var budget = self.oneRunBudget
            self.inAction = true

            let retryBudgetMax = 100

            self.forDeletion.removeAll(keepingCapacity: true)

            DispatchQueue.global().async {

                allPhotos.enumerateObjects { (asset, idx, stop) in
                    guard budget > 0 else {
                        print("Budget depleted. Cannot perform operation.")
                        stop.pointee = true
                        return
                    }

                    var retryBudget = retryBudgetMax

                    while retryBudget > 0 {
                        do {
                            try self.handle(the: asset)
                            break
                        } catch {
                            print("An error occurred: \(error)")
                            retryBudget -= 1
                            if retryBudget > 0 {
                                DispatchQueue.main.async {
                                    self.retries += 1
                                }
                            }
                        }
                    }

                    DispatchQueue.main.async {
                        self.forDeletion.append(asset)

                        self.completed = (self.completed ?? 0) + 1

                        let durationInSeconds = Date().timeIntervalSince(startTime)
                        let durationInMinutes = durationInSeconds / 60
                        self.operationsPerMinute = Double(self.completed ?? 0) / durationInMinutes
                        if let operationsPerMinute = self.operationsPerMinute, operationsPerMinute > 0 {
                            self.eta = (Double(Int(self.oneRunBudget)) / operationsPerMinute)
                        }
                    }

                    budget -= 1
                }

                DispatchQueue.main.async {
                    // Optionally, delete the photo after backing it up
                    // Remember to run deletion code on the main thread if affecting the UI
                    print("Deleting \(self.forDeletion.count) assets...")
                    PHPhotoLibrary.shared().performChanges({
                        PHAssetChangeRequest.deleteAssets(self.forDeletion as NSArray)
                    }) { success, error in
                        if success {
                            print("Successfully deleted \(self.forDeletion.count) assets")
                        } else if let error = error {
                            print("Failed to delete \(self.forDeletion.count) assets: \(error.localizedDescription)")
                        }
                    }

                    self.inAction = false
                }
            }

            //handle(the: allPhotos.firstObject!)

            print("Done")
        }
    }

    func checkIfFileExists(at serverURL: URL, bytes: Int) -> Bool {

//        print("checkIfFileExists...")

        var request = URLRequest(url: serverURL)
        request.httpMethod = "HEAD"

        let (_, response, error) = s.synchronousDataTask(with: request)

        guard error == nil else {
            DispatchQueue.main.async {
                print("Error checking file: \(error!.localizedDescription)")
            }
            return false
        }

        return (response as? HTTPURLResponse)?.statusCode == 200 &&
        (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Length") == "\(bytes)"
    }

    enum MyError: Error {
        case runtimeError(String)
    }

    func uploadFile(_ imageData: Data, at uploadURL: URL) throws {
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

//        print("Uploading image...")

        let (_, response, error) = s.synchronousUploadTask(with: request, data: imageData)

        if let error = error {
            print("Upload error: \(error)")
            throw MyError.runtimeError("Upload error: \(error)")
        }
        guard let response = response as? HTTPURLResponse,
              (200...299).contains(response.statusCode) else {
            print("Server error")
            throw MyError.runtimeError("Server error")
        }
        print("Upload successful")
    }

    func requestImageData(for asset: PHAsset) throws -> (Data?, [AnyHashable : Any]?) {

        var data: Data?
        var error: [AnyHashable : Any]?
        let options = PHImageRequestOptions()
        options.version = .original
        options.isSynchronous = true

//        print("Requesting Image Data")

        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) {
            data = $0
            error = $3
//            print("requestImageData callback")
        }

//        print("requestImageData done")

        return (data, error)
    }

    func handle(the asset: PHAsset) throws -> Void {
        let fileName = PHAssetResource.assetResources(for: asset)[0].originalFilename
        print("\(asset.localIdentifier) : \(fileName) - \(asset.creationDate?.description ?? "unknown")")
        // For each photo, request the image data

        let uploadURL = URL(string: "http://Aleksandrs-MacBook-Air.local:8080/\(fileName.replacingOccurrences(of: "/", with: "_"))")!

        let (data, error) = try requestImageData(for: asset)
//                if let error = error {
//                    print("requestImageData error: \(error)")
//                    return
//                }
        if let data = data {
            DispatchQueue.main.async {
                self.img = UIImage(data: data) ?? UIImage()
            }
            if (checkIfFileExists(at: uploadURL, bytes: data.count)) {
                print("File already exists at \(uploadURL) and size matches")
                return
            } else {
                print("File does not exist at \(uploadURL) or size does not match")
                try uploadFile(data, at: uploadURL)
            }
        }
    }
}

#Preview {
    ContentView()
}
