import Flutter
import UIKit
import Combine
import VitalCore
import VitalHealthKit

private let jsonEncoder: JSONEncoder = {
  let jsonEncoder = JSONEncoder()
  jsonEncoder.outputFormatting = .withoutEscapingSlashes
  jsonEncoder.dateEncodingStrategy = .iso8601
  return jsonEncoder
}()

public class SwiftVitalHealthKitPlugin: NSObject, FlutterPlugin {
  private let channel: FlutterMethodChannel
  private var cancellable: Cancellable? = nil
  private var flutterRunning = true

 init(_ channel: FlutterMethodChannel){
    self.channel = channel;
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "vital_health_kit", binaryMessenger: registrar.messenger())
    let instance = SwiftVitalHealthKitPlugin(channel)

    registrar.publish(instance)

    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addApplicationDelegate(instance)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    flutterRunning = false
    cancellable?.cancel()
  }

  // Because the Plugin inherits from FlutterPlugin and it is added via `addApplicationDelegate`
  // When the app terminates, the cancellable should be cancelled
  public func applicationWillTerminate(_ application: UIApplication) {
    flutterRunning = false
    cancellable?.cancel()
  }

  public static func detachFromEngineForRegistrar(registrar: FlutterPluginRegistrar) {
    print("detachFromEngineForRegistrar")
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
      case "writeHealthKitData":
        writeHealthKitData(call.arguments as! [AnyObject], result: result)
        return
      case "configureClient":
        configureClient(call.arguments as! [AnyObject], result: result)
        return
      case "configureHealthkit":
        configureHealthkit(call.arguments as! [AnyObject], result: result)
        return
      case "setUserId":
        Task {
          await VitalClient.setUserId(UUID(uuidString: call.arguments as! String)!)
          result(nil)
        }
        return
      case "cleanUp":
        Task {
          await VitalHealthKitClient.shared.cleanUp()
          result(nil)
        }
        return
      case "hasAskedForPermission":
        let resource = call.arguments as! String
        hasAskedForPermission(resource: resource, result: result)
        return

      case "isUserConnected":
        do {
          let providerString = call.arguments as! String
          let provider = try mapProviderToVitalProvider(providerString)

          Task {
            let isConnected = try await VitalClient.shared.isUserConnected(to: provider)
            result(isConnected)
          }
        } catch VitalError.UnsupportedProvider(let errorMessage) {
          result(encode(ErrorResult(code: "UnsupportedProvider", message: errorMessage)))
        } catch {
          result(encode(ErrorResult(code: error.localizedDescription)))
        }
        return

      case "ask":
        ask(call.arguments as! [AnyObject], result: result)
        return
      case "syncData":
        syncData(resources: call.arguments as? [String], result: result)
        result(nil)
        return
      case "subscribeToStatus":
        subscribeToStatus()
        result(nil)
        return
      case "unsubscribeFromStatus":
        cancellable?.cancel()
        result(nil)
        return
      default:
        break
    }
    result(FlutterError.init(code: "Unsupported method",
                             message: "Method not supported \(call.method)",
                             details: nil))
  }

  private func writeHealthKitData(_ arguments: [AnyObject], result: @escaping FlutterResult){
    do {
    let resourceString: String = arguments[0] as! String
    let resource = try mapResourceToVitalResource(resourceString)

    let value: Double = arguments[1] as! Double

    let startDate = Date(timeIntervalSince1970: Double(arguments[2] as! Int))
    let endDate = Date(timeIntervalSince1970: Double(arguments[3] as! Int))

    let dataInput: DataInput 

    switch resource {
      case .nutrition(.water):
        dataInput = .water(milliliters: Int(value))
      default: 
        fatalError("\(resource) not supported for writing to HealthKit")
    }

    Task {
      try await VitalHealthKitClient.shared.write(input: dataInput, startDate: startDate, endDate: endDate)
      result(nil)
    }
    } catch VitalError.UnsupportedResource(let errorMessage) {
      result(encode(ErrorResult(code: "UnsupportedResource", message: errorMessage)))
    } catch {
      result(encode(ErrorResult(code: error.localizedDescription)))
    }
  }

  private func configureClient(_ arguments: [AnyObject], result: @escaping FlutterResult){
    let apiKey: String = arguments[0] as! String
    let region: String  = arguments[1] as! String
    let environment: String = arguments[2] as! String

    Task {
      await VitalClient.configure(
        apiKey: apiKey,
        environment: try resolveEnvironment(region: region, environment: environment)
      )
      result(nil)
    }
  }

  private func configureHealthkit(_ arguments: [AnyObject], result: @escaping FlutterResult){
    let backgroundDeliveryEnabled: Bool = arguments[0] as! Bool
    let logsEnabled = arguments[1] as! Bool
    let numberOfDaysToBackFill: Int = arguments[2] as! Int
    let modeString: String = arguments[3] as! String

    Task {
      let mode = try mapToMode(modeString)

      await VitalHealthKitClient.configure(
        .init(
          backgroundDeliveryEnabled: backgroundDeliveryEnabled,
          numberOfDaysToBackFill: numberOfDaysToBackFill,
          logsEnabled: logsEnabled,
          mode: mode
        )
      )

      result(nil)
    }
  }

  private func hasAskedForPermission(resource: String, result: @escaping FlutterResult) {
    do {
      let resource = try mapResourceToVitalResource(resource)
      let value: Bool = VitalHealthKitClient.shared.hasAskedForPermission(resource: resource)
      result(value)
    } catch VitalError.UnsupportedResource(let errorMessage) {
      result(encode(ErrorResult(code: "UnsupportedResource", message: errorMessage)))
    } catch {
      result(encode(ErrorResult(code: "Unknown error")))
    }
  }

  private func ask(_ arguments: [AnyObject], result: @escaping FlutterResult){

    let readResourcesString: [String] = arguments[0] as! [String]
    let writeResourcesString: [String] = arguments[1] as! [String]

    Task {
        let readResources = readResourcesString.map { try! mapResourceToVitalResource($0) }
        let writeResources = writeResourcesString.map { try! mapResourceToWritableVitalResource($0) }

        let outcome = await VitalHealthKitClient.shared.ask(readPermissions: readResources, writePermissions: writeResources)
        switch outcome {
          case .success:
            result(nil)
          case .failure(let message):
            result(encode(ErrorResult(code: "failure", message: message)))
          case .healthKitNotAvailable:
            result(encode(ErrorResult(code: "healthKitNotAvailable", message: "healthKitNotAvailable")))
        }
    }
  }

  private func syncData(resources: [String]?, result: @escaping FlutterResult){
    do {
      if let res = resources {
        try VitalHealthKitClient.shared.syncData(for: res.map { try mapResourceToVitalResource($0) })
      } else {
        VitalHealthKitClient.shared.syncData()
      }
      result(nil)
    } catch VitalError.UnsupportedResource(let errorMessage) {
      result(encode(ErrorResult(code: "UnsupportedResource", message: errorMessage)))
    } catch {
      result(encode(ErrorResult(code: "Unknown error")))
    }
  }

  private func subscribeToStatus(){
    cancellable?.cancel()
    cancellable = VitalHealthKitClient.shared.status.sink {[weak self] value in
      guard self?.flutterRunning ?? false else {
        return
      }

      self?.channel.invokeMethod("sendStatus", arguments: mapStatusToArguments(value))
    }
  }
}

struct AnyEncodable: Encodable {
  let value: Encodable

  func encode(to encoder: Encoder) throws {
    try value.encode(to: encoder)
  }
}

struct ErrorResult: Encodable {
  let code: String
  let message: String?

  init(code: String, message: String? = nil){
    self.code = code
    self.message = message
  }
}

enum VitalError: Error {
  case UnsupportedRegion(String)
  case UnsupportedEnvironment(String)
  case UnsupportedResource(String)
  case UnsupportedDataPushMode(String)
  case UnsupportedProvider(String)
  case UnsupportedBrand(String)
  case UnsupportedKind(String)
}

private func mapStatusToArguments(_ status: VitalHealthKitClient.Status) -> [Any?]{
  switch status {
    case .failedSyncing(let resource, let error):
      return ["failedSyncing", mapVitalResourceToResource(resource), error?.localizedDescription]
    case .successSyncing(let resource, let data):
      return ["successSyncing", mapVitalResourceToResource(resource), encodePostResourceData(data)]
    case .nothingToSync(let resource):
      return ["nothingToSync", mapVitalResourceToResource(resource), nil]
    case .syncing(let resource):
      return ["syncing", mapVitalResourceToResource(resource), nil]
    case .syncingCompleted:
      return ["syncingCompleted", nil, nil]
  }
}

private func mapVitalResourceToResource(_ resource: VitalResource) -> String {
  switch resource {
    case .profile:
      return "profile"
    case .body:
      return "body"
    case .workout:
      return "workout"
    case .activity:
      return "activity"
    case .sleep:
      return "sleep"
    case .vitals(let type):
      switch type {
        case .glucose:
          return "glucose"
        case .bloodPressure:
          return "bloodPressure"
        case .hearthRate:
          return "heartRate"
      }
    case .individual(let type):
      switch type {
        case .steps:
          return "steps"
        case .activeEnergyBurned:
          return "activeEnergyBurned"
        case .basalEnergyBurned:
          return "basalEnergyBurned"
        case .floorsClimbed:
          return "floorsClimbed"
        case .distanceWalkingRunning:
          return "distanceWalkingRunning"
        case .vo2Max:
          return "vo2Max"
        case .weight:
          return "weight"
        case .bodyFat:
          return "bodyFat"
      }

    case .nutrition(let type):
      switch type {
        case .water:
          return "water"
      }
  }
}

private func encodePostResourceData(_ data: ProcessedResourceData) -> String? {
  let payload: String? = encode(data.payload)
  return payload
}

private func resolveEnvironment(region: String, environment: String) throws -> Environment {
  switch region {
    case "eu":
      switch environment {
        case "dev":
          return Environment.dev(.eu)
        case "sandbox":
          return Environment.sandbox(.eu)
        case "production":
          return Environment.production(.eu)
        default:
          throw VitalError.UnsupportedEnvironment("\(environment)")
      }
    case "us":
      switch environment {
        case "dev":
          return Environment.dev(.us)
        case "sandbox":
          return Environment.sandbox(.us)
        case "production":
          return Environment.production(.us)
        default:
          throw VitalError.UnsupportedEnvironment("\(environment)")
      }
    default:
      throw VitalError.UnsupportedRegion("\(region)")
  }
}

private func mapToMode(_ mode: String) throws -> VitalHealthKitClient.Configuration.DataPushMode {
  switch mode {
    case "manual":
      return .manual
    case "automatic":
      return .automatic
    default:
      throw VitalError.UnsupportedDataPushMode("\(mode)")
  }
}

private func mapResourceToVitalResource(_ name: String) throws -> VitalResource {
  switch name {
    case "profile":
      return .profile
    case "body":
      return .body
    case "workout":
      return .workout
    case "activity":
      return .activity
    case "sleep":
      return .sleep
    case "glucose":
      return .vitals(.glucose)
    case "bloodPressure":
      return .vitals(.bloodPressure)
    case "heartRate":
      return .vitals(.hearthRate)
    case "steps":
      return .individual(.steps)
    case "activeEnergyBurned":
      return .individual(.activeEnergyBurned)
    case "basalEnergyBurned":
      return .individual(.basalEnergyBurned)
    case "floorsClimbed":
      return .individual(.floorsClimbed)
    case "distanceWalkingRunning":
      return .individual(.distanceWalkingRunning)
    case "vo2Max":
      return .individual(.vo2Max)
    case "weight":
      return .individual(.weight)
    case "bodyFat":
      return .individual(.bodyFat)
    case "water":
      return .nutrition(.water)
    default:
      throw VitalError.UnsupportedResource(name)
  }
}

private func mapResourceToWritableVitalResource(_ name: String) throws -> WritableVitalResource {
  switch name {
    case "water":
      return .water
    default:
      throw VitalError.UnsupportedResource(name)
  }
}

private func mapProviderToVitalProvider(_ provider: String) throws -> Provider {
  guard let provider = Provider(rawValue: provider) else {
    throw VitalError.UnsupportedProvider(provider)
  }

  return provider
}

private func encode(_ encodable: Encodable) -> String? {
  let json: String?
  let jsonEncoder = JSONEncoder()

  if let data = try? encode(encodable, encoder: jsonEncoder) {
    json = String(data: data, encoding: .utf8)
  } else {
    json = nil
  }
  return json
}

private func encode(_ value: Encodable, encoder: JSONEncoder) throws -> Data? {
  if let data = value as? Data {
    return data
  } else if let string = value as? String {
    return string.data(using: .utf8)
  } else {
    return try encoder.encode(AnyEncodable(value: value))
  }
}
