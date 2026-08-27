import CoreGraphics
import Observation

@MainActor
@Observable
final class AppModel {
  typealias Screen = AppScreen
  nonisolated static let windowSize = CGSize(width: 845, height: 737)

  var screen: AppScreen = .homeFindings
  var toast: String?
  var correction = ""
  var excludedItems = ["1Password", "Keychain Access", "Private notes", "Personal finance"]
  var capturePaused = false

  var selectedScreen: AppScreen {
    get { screen }
    set { screen = newValue }
  }

  var menuBarSymbolName: String {
    switch screen {
    case .menuAttention, .homeAttention, .setupDenied:
      "exclamationmark.circle"
    case .menuDetailed, .homeWatching:
      "scope"
    case .menuApproval, .consentReview, .providerChoice:
      "checkmark.circle"
    default:
      "circle.dotted.circle"
    }
  }

  func show(_ screen: AppScreen) { self.screen = screen }
  func select(_ screen: AppScreen) { self.screen = screen }
  func notify(_ message: String) { toast = message }
}

enum AppScreen: String, CaseIterable, Identifiable, Sendable {
  case setupPermission, setupWaiting, setupDenied
  case homeEmpty, homeFindings, homePaused, homeAttention, homeAnalyzing
  case homeReady, homeQuietResult, homeContextNudge
  case consentReview, providerChoice
  case settings, settingsNeverCapture
  case findingComplete, findingIncomplete, findingCorrection, findingSaved
  case homeWatching, homeWatchingDone
  case menuCapturing, menuAttention, menuDetailed, menuApproval
  case toastSpec

  var id: String { rawValue }

  var title: String {
    rawValue
      .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 · $2", options: .regularExpression)
      .replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression)
      .trimmingCharacters(in: .whitespaces)
      .capitalized
  }

  var figmaID: String {
    switch self {
    case .setupPermission: "10:22"
    case .setupWaiting: "27:1034"
    case .setupDenied: "27:1069"
    case .homeEmpty: "13:22"
    case .homeFindings: "13:46"
    case .homePaused: "13:93"
    case .homeAttention: "13:140"
    case .homeAnalyzing: "13:194"
    case .homeReady: "11:113"
    case .homeQuietResult: "11:137"
    case .homeContextNudge: "11:183"
    case .consentReview: "29:6533"
    case .providerChoice: "29:6593"
    case .settings: "29:6787"
    case .findingComplete: "34:248"
    case .findingIncomplete: "36:141"
    case .findingCorrection: "36:175"
    case .settingsNeverCapture: "61:107"
    case .homeWatching: "65:110"
    case .homeWatchingDone: "65:164"
    case .findingSaved: "65:225"
    case .menuCapturing: "66:128"
    case .menuAttention: "66:151"
    case .menuDetailed: "66:174"
    case .menuApproval: "66:197"
    case .toastSpec: "66:220"
    }
  }

  var figmaSize: CGSize {
    switch self {
    case .menuCapturing, .menuAttention, .menuDetailed, .menuApproval:
      CGSize(width: 400, height: 480)
    case .toastSpec:
      CGSize(width: 560, height: 360)
    default:
      AppModel.windowSize
    }
  }

  // Compatibility names matching the raw Figma frame taxonomy.
  static let screenRecordingPermission = Self.setupPermission
  static let permissionNotYetRequested = Self.setupWaiting
  static let permissionDenied = Self.setupDenied
  static let homeCapturingEmpty = Self.homeEmpty
  static let homeCapturingFindings = Self.homeFindings
  static let homeNeedsAttention = Self.homeAttention
  static let homeReadyToAnalyze = Self.homeReady
  static let homeQuietResultBanner = Self.homeQuietResult
  static let consentChooseProvider = Self.providerChoice
  static let findingDetailComplete = Self.findingComplete
  static let findingDetailIncomplete = Self.findingIncomplete
  static let findingDetailCorrection = Self.findingCorrection
  static let findingDetailSaved = Self.findingSaved
  static let homeWatchingClosely = Self.homeWatching
  static let menuBarCapturing = Self.menuCapturing
  static let menuBarAttention = Self.menuAttention
  static let menuBarDetailed = Self.menuDetailed
  static let menuBarApproval = Self.menuApproval
}
