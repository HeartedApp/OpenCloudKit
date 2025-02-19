//
//  CKURLRequest.swift
//  OpenCloudKit
//
//  Created by Benjamin Johnson on 23/07/2016.
//
//

import Foundation
import FoundationNetworking

enum CKOperationRequestType: String {
    case records
    case assets
    case zones
    case users
    case lookup
    case subscriptions
    case tokens
}

enum CKURLRequestError {
    case JSONParse(NSError)
    case networkError(NSError)
}

enum CKURLRequestResult {
    case success([String: Any])
    case error(CKError)
}

class CKURLRequest: NSObject {
    
    var accountInfoProvider: CKAccountInfoProvider?
    
    var databaseScope: CKDatabaseScope = .public

    var dateRequestWentOut: Date?
    
    var httpMethod: String = "POST"
    
    var isFinished: Bool = false
    
    var requiresSigniture: Bool = false
    
    var path: String = ""
    
    var requestContentType: String = "application/json; charset=utf-8"
    
    var requestProperties:[String: Any]?
    
    var urlSessionTask: URLSessionDataTask?
    
    var allowsAnonymousAccount = false
    
    var operationType: CKOperationRequestType = .records
   
    var metricsDelegate: CKURLRequestMetricsDelegate?
    
    var metrics: CKOperationMetrics?
    
    var completionBlock: ((CKURLRequestResult) -> ())?
    
    var request: URLRequest {
        get {
            var urlRequest = URLRequest(url: url)

            if let properties = requestProperties {
                
                let jsonData: Data = try! JSONSerialization.data(withJSONObject: properties.bridge(), options: [])
                
                urlRequest.httpBody = jsonData
                urlRequest.httpMethod = httpMethod
                urlRequest.addValue(requestContentType, forHTTPHeaderField: "Content-Type")
                
                let dataString = NSString(data: jsonData, encoding: String.Encoding.utf8.rawValue)
            
                CloudKit.debugPrint(dataString as Any)
               
                if let serverAccount = accountInfoProvider as? CKServerAccount {
                    // Sign Request 
                    if let signedRequest  = CKServerRequestAuth.authenicateServer(forRequest: urlRequest, withServerToServerKeyAuth: serverAccount.serverToServerAuth) {
                        urlRequest = signedRequest
                    }
                }
            
            } else {
                urlRequest.httpMethod = httpMethod

            }
          
        
            return urlRequest
        }
    }
    
    
    var sessionConfiguration: URLSessionConfiguration  {
        
        let configuration = URLSessionConfiguration.default
        
        return configuration
    }
    
    var requiresTokenRegistration: Bool {
        return false
    }
    
    var serverType: CKServerType {
        return CKServerType.database
    }
    
    var url: URL {
        get {
            let accountInfo = accountInfoProvider ?? CloudKit.shared.defaultAccount!
            var baseURL: String
            switch serverType {
            case .database:
                baseURL =  accountInfo.containerInfo.publicCloudDBURL(databaseScope: databaseScope).appendingPathComponent("\(operationType)/\(path)").absoluteString
            case .device:
                let account = accountInfo as! CKAccount
                baseURL = account.baseURL(forServerType: serverType)
                    .appendingPathComponent(accountInfo.containerInfo.containerID)
                    .appendingPathComponent("\(accountInfo.containerInfo.environment)")
                    .appendingPathComponent("\(operationType)/\(path)").absoluteString
                
            default:
                fatalError("Type not supported")
            }
            
            
          //  var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
            switch accountInfo.accountType {
            case .server:
                break
            case .anoymous, .primary:
              //  urlComponents.queryItems = []
                // if let accountInfo = accountInfoProvider {
                
              //  let apiTokenItem = URLQueryItem(name: "ckAPIToken", value: accountInfo.cloudKitAuthToken)
               // urlComponents.queryItems?.append(apiTokenItem)
                
                baseURL += "?ckAPIToken=\(accountInfo.cloudKitAuthToken ?? "")"
                
                if let icloudAuthToken = accountInfo.iCloudAuthToken {
                    
                    //let webAuthTokenQueryItem = URLQueryItem(name: "ckWebAuthToken", value: icloudAuthToken)
                   // urlComponents.queryItems?.append(webAuthTokenQueryItem)
                    let encodedWebAuthToken = icloudAuthToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!.replacingOccurrences(of: "+", with: "%2B")
                    baseURL += "&ckWebAuthToken=\(encodedWebAuthToken)"
                    
                }

                
            }
            
            // Perform Encoding
           // urlComponents.percentEncodedQuery = urlComponents.percentEncodedQuery?.replacingOccurrences(of:"+", with: "%2B")
            //CloudKit.debugPrint(urlComponents.url!)
            return URL(string: baseURL)!
        }
    }

    var resultData = Data()
    
    func performRequest() {
        dateRequestWentOut = Date()
        
        // maybe could have passed in CKOperation's callbackQueue as the delegateQueue, would have simplified the code
        let session = URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: nil)

        urlSessionTask = session.dataTask(with: request)
        urlSessionTask!.resume()
        session.finishTasksAndInvalidate()
    }
    
    func cancel() {
        urlSessionTask?.cancel()
    }
    
    func requestDidParseNodeFailure() {}
    
    func requestDidParseObject() {}
    
//    var requestOperationClasses:[CKRequest.Type] {
//        return []
//    }
    
}

extension CKURLRequest: URLSessionDataDelegate {
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {

        // append the data to the end
        resultData.append(data)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        
        metrics = CKOperationMetrics(bytesDownloaded: 0, bytesUploaded: UInt(totalBytesSent), duration: 0, startDate: dateRequestWentOut!)
        
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            CloudKit.debugPrint(error)
            // Handle Error
            completionBlock?(.error(.network(error)))
        } else {

            if let operationMetrics = metrics {
                metrics?.bytesDownloaded = UInt(resultData.count)
                metricsDelegate?.requestDidFinish(withMetrics: operationMetrics)
            }

            // Parse JSON
            do {
                let jsonObject = try JSONSerialization.jsonObject(with: resultData, options: []) as! [String: Any]
            
                CloudKit.debugPrint(jsonObject)

                // Call completion block
                if let _ = CKErrorDictionary(dictionary: jsonObject) {
                    completionBlock?(.error(CKError.server(jsonObject)))
                } else {
                    let result = CKURLRequestResult.success(jsonObject)
                    completionBlock?(result)
                }
        
            } catch let error {
                completionBlock?(.error(.parse(error)))
            }

        }
    }
    
}

protocol CKAccountInfoProvider {
    var accountType: CKAccountType { get }
    var cloudKitAuthToken: String? { get }
    var iCloudAuthToken: String? { get }
    var containerInfo: CKContainerInfo { get }
}

struct CKServerInfo {
    static let path = "https://api.apple-cloudkit.com"
    
    static let version = "1"
}



