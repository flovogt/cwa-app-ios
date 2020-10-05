import Foundation


class CachingHTTPClient: AppConfigurationFetching {
	/// The client configuration - mostly server endpoints per environment
	let configuration: HTTPClient.Configuration

	/// The underlying URLSession for all network requests
	let session: URLSession

	/// Verifier for the fetched & signed protobuf packages
	let packageVerifier: SAPDownloadedPackage.Verifier


	/// Initializer for the caching client.
	///
	/// - Parameters:
	///   - clientConfiguration: The client configuration for the client.
	///   - session: An optional session to use for network requests. Default is based on a predefined configuration.
	///   - packageVerifier: The verifier to use for package validation.
	init(
		clientConfiguration: HTTPClient.Configuration,
		session: URLSession = URLSession(configuration: .cachingSessionConfiguration()),
		packageVerifier: SAPDownloadedPackage.Verifier = SAPDownloadedPackage.Verifier()) {
		self.session = session
		self.configuration = clientConfiguration
		self.packageVerifier = packageVerifier
	}

	// MARK: - AppConfigurationFetching

	/// Fetches an application configuration file
	/// - Parameters:
	///   - etag: an optional ETag to download only versions that differ the given tag
	///   - completion: result handler
	func fetchAppConfiguration(etag: String? = nil, completion: @escaping AppConfigResultHandler) {
		// ETag
		var headers: [String: String]?
		if let etag = etag {
			headers = ["If-None-Match": etag]
		}

		session.GET(configuration.configurationURL, extraHeaders: headers) { result in
			switch result {
			case .success(let response):
				// content not modified?
				guard response.statusCode != 304 else {
					completion(.failure(CachedAppConfiguration.CacheError.notModified))
					return
				}

				// has data?
				guard
					let data = response.body,
					let package = SAPDownloadedPackage(compressedData: data)
				else {
					let error = CachedAppConfiguration.CacheError.dataFetchError(message: "Failed to create downloaded package for app config.")
					completion(.failure(error))
					return
				}

				// data verified?
				guard self.packageVerifier(package) else {
					let error = CachedAppConfiguration.CacheError.dataVerificationError(message: "Failed to verify app config signature")
					completion(.failure(error))
					return
				}

				// serialize config
				do {
					let config = try SAP_ApplicationConfiguration(serializedData: package.bin)
					let eTag = response.httpResponse.value(forHTTPHeaderField: "ETag")
					let configurationResponse = AppConfigurationFetchingResponse(config, eTag)
					completion(.success(configurationResponse))
				} catch {
					completion(.failure(error))
				}
			case .failure(let error):
				completion(.failure(error))
			}
		}
	}
}
