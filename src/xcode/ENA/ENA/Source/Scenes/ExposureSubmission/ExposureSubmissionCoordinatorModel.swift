import Foundation
import UIKit

class ExposureSubmissionCoordinatorModel {

	// MARK: - Init

	init(exposureSubmissionService: ExposureSubmissionService, appConfigurationProvider: AppConfigurationProviding) {
		self.exposureSubmissionService = exposureSubmissionService
		self.appConfigurationProvider = appConfigurationProvider
	}

	// MARK: - Internal

	let exposureSubmissionService: ExposureSubmissionService
	let appConfigurationProvider: AppConfigurationProviding

	var supportedCountries: [Country] = []

	var shouldShowSymptomsOnsetScreen = false

	var exposureSubmissionServiceHasRegistrationToken: Bool {
		exposureSubmissionService.hasRegistrationToken()
	}

	func symptomsOptionSelected(
		selectedSymptomsOption: ExposureSubmissionSymptomsViewController.SymptomsOption,
		isLoading: @escaping (Bool) -> Void,
		onSuccess: @escaping () -> Void,
		onError: @escaping (ExposureSubmissionError) -> Void
	) {
		switch selectedSymptomsOption {
		case .yes:
			shouldShowSymptomsOnsetScreen = true
			onSuccess()
		case .no:
			symptomsOnset = .nonSymptomatic
			shouldShowSymptomsOnsetScreen = false
			loadSupportedCountries(isLoading: isLoading, onSuccess: onSuccess, onError: onError)
		case .preferNotToSay:
			symptomsOnset = .noInformation
			shouldShowSymptomsOnsetScreen = false
			loadSupportedCountries(isLoading: isLoading, onSuccess: onSuccess, onError: onError)
		}
	}

	func symptomsOnsetOptionSelected(
		selectedSymptomsOnsetOption: ExposureSubmissionSymptomsOnsetViewController.SymptomsOnsetOption,
		isLoading: @escaping (Bool) -> Void,
		onSuccess: @escaping () -> Void,
		onError: @escaping (ExposureSubmissionError) -> Void
	) {
		switch selectedSymptomsOnsetOption {
		case .exactDate(let date):
			guard let daysSinceOnset = Calendar.gregorian().dateComponents([.day], from: date, to: Date()).day else { fatalError("Getting days since onset from date failed") }
			symptomsOnset = .daysSinceOnset(daysSinceOnset)
		case .lastSevenDays:
			symptomsOnset = .lastSevenDays
		case .oneToTwoWeeksAgo:
			symptomsOnset = .oneToTwoWeeksAgo
		case .moreThanTwoWeeksAgo:
			symptomsOnset = .moreThanTwoWeeksAgo
		case .preferNotToSay:
			symptomsOnset = .symptomaticWithUnknownOnset
		}

		loadSupportedCountries(isLoading: isLoading, onSuccess: onSuccess, onError: onError)
	}


	func warnOthersConsentGiven(
		isLoading: @escaping (Bool) -> Void,
		onSuccess: @escaping () -> Void,
		onError: @escaping (ExposureSubmissionError) -> Void
	) {
		startSubmitProcess(
			isLoading: isLoading,
			onSuccess: onSuccess,
			onError: onError
		)
	}

	// MARK: - Private

	private var symptomsOnset: SymptomsOnset = .noInformation
	private var consentToFederationGiven: Bool = false

	private func loadSupportedCountries(
		isLoading: @escaping (Bool) -> Void,
		onSuccess: @escaping () -> Void,
		onError: @escaping (ExposureSubmissionError) -> Void
	) {
		isLoading(true)
		appConfigurationProvider.appConfiguration { result in
			isLoading(false)

			switch result {
			case .success(let config):
				let countries = config.supportedCountries.compactMap({ Country(countryCode: $0) })
				if countries.isEmpty {
					self.supportedCountries = [.defaultCountry()]
				} else {
					self.supportedCountries = countries
				}
				onSuccess()
			case .failure:
				onError(.noAppConfiguration)
			}
		}
	}

	private func startSubmitProcess(
		isLoading: @escaping (Bool) -> Void,
		onSuccess: @escaping () -> Void,
		onError: @escaping (ExposureSubmissionError) -> Void
	) {
		isLoading(true)

		exposureSubmissionService.submitExposure(
			symptomsOnset: symptomsOnset,
			consentToFederation: consentToFederationGiven,
			visitedCountries: supportedCountries,
			completionHandler: { error in
				isLoading(false)

				switch error {
				// If the user doesn`t allow the TEKs to be shared with the app, we stay on the screen (https://jira.itc.sap.com/browse/EXPOSUREAPP-2293)
				case .notAuthorized:
					return

				// We continue the regular flow even if there are no keys collected.
				case .none, .noKeys:
					onSuccess()

				case .some(let error):
					logError(message: "error: \(error.localizedDescription)", level: .error)
					onError(error)
				}
			}
		)
	}

}
