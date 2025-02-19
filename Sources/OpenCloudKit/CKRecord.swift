//
//  CKRecord.swift
//  OpenCloudKit
//
//  Created by Benjamin Johnson on 6/07/2016.
//
//

import Foundation

public let CKRecordTypeUserRecord: String = "Users"
public protocol CKRecordFieldProvider {
    var recordFieldDictionary: [String: Any] { get }
}
extension CKRecordFieldProvider where Self: Any {
    public var recordFieldDictionary: [String: Any] {
        return ["value": self]
    }
}
/*
extension CKRecordFieldProvider where Self: CustomDictionaryConvertible {
    public var recordFieldDictionary: [String: Any] {
        return ["value": self.dictionary]
    }
}
*/
public protocol CKRecordValue : CKRecordFieldProvider {}


public class CKRecord: NSObject, NSSecureCoding {

    var values: [String: CKRecordValue] = [:]

    public let recordType: String

    public let recordID: CKRecordID

    public var recordChangeTag: String?

    /* This is a User Record recordID, identifying the user that created this record. */
    public var creatorUserRecordID: CKRecordID?

    public var creationDate = Date()

    /* This is a User Record recordID, identifying the user that last modified this record. */
    public var lastModifiedUserRecordID: CKRecordID?

    public var modificationDate: Date?

    private var changedKeysSet = NSMutableSet()

    public var parent: CKReference?

    public convenience init(recordType: String) {
        let UUID = NSUUID().uuidString
        self.init(recordType: recordType, recordID: CKRecordID(recordName: UUID))
    }

    public init(recordType: String, recordID: CKRecordID) {
        self.recordID = recordID
        self.recordType = recordType
    }

    public func object(forKey key: String) -> CKRecordValue? {
        return values[key]
    }

    public func setObject(_ object: CKRecordValue?, forKey key: String) {

        let containsKey = changedKeysSet.contains(key)


        if !containsKey {
            changedKeysSet.add(key.bridge())
        }

        switch object {
        case let asset as CKAsset:
            asset.recordID = self.recordID
        default:
            break
        }

        values[key] = object
    }

    public func setObject(_ array: [CKRecordValue]?, forKey key: String) {
        if let arrayValue = array {
            let foundationArray = NSArray(array: arrayValue)
            setObject(foundationArray, forKey: key)
        } else {
            setObject(array, forKey: key)
        }
    }

    public func allKeys() -> [String] {
       return Array(values.keys)
    }

    public subscript(key: String) -> CKRecordValue? {
        get {
            return object(forKey: key)
        }
        set(newValue) {
            setObject(newValue, forKey: key)
        }
    }

    public func changedKeys() -> [String] {
        var changedKeysArray: [String] = []
        for changedKey in changedKeysSet.allObjects {
            if let key = (changedKey as? NSString)?.bridge() {
                changedKeysArray.append(key)
            }
        }

        return changedKeysArray
    }


    override public var description: String {
        return "<\(type(of: self)): ; recordType = \(recordType);recordID = \(recordID); values = \(values)>"
    }

    public override var debugDescription: String {
        return"<\(type(of: self)); recordType = \(recordType);recordID = \(recordID); values = \(values)>"
    }

    init?(recordDictionary: [String: Any], recordID: CKRecordID? = nil) {

        guard let recordName = recordDictionary[CKRecordDictionary.recordName] as? String,
            let recordType = recordDictionary[CKRecordDictionary.recordType] as? String
            else {
                return nil
        }

        // Parse ZoneID Dictionary into CKRecordZoneID
        let zoneID: CKRecordZoneID
        if let zoneIDDictionary = recordDictionary[CKRecordDictionary.zoneID] as? [String: Any] {
            zoneID = CKRecordZoneID(dictionary: zoneIDDictionary)!
        } else {
            zoneID = CKRecordZoneID(zoneName: CKRecordZoneDefaultName, ownerName: "_defaultOwner")
        }

        if let recordID = recordID {
            self.recordID = recordID
        } else {
            let recordID = CKRecordID(recordName: recordName, zoneID: zoneID)
            self.recordID = recordID
        }

        self.recordType = recordType

        // Parse Record Change Tag
        if let changeTag = recordDictionary[CKRecordDictionary.recordChangeTag] as? String {
            recordChangeTag = changeTag
        }

        // Parse Created Dictionary
        if let createdDictionary = recordDictionary[CKRecordDictionary.created] as? [String: Any], let created = CKRecordLog(dictionary: createdDictionary) {
            self.creatorUserRecordID = CKRecordID(recordName: created.userRecordName)
            self.creationDate = Date(timeIntervalSince1970: Double(created.timestamp) / 1000)
        }

        // Parse Modified Dictionary
        if let modifiedDictionary = recordDictionary[CKRecordDictionary.modified] as? [String: Any], let modified = CKRecordLog(dictionary: modifiedDictionary) {
            self.lastModifiedUserRecordID = CKRecordID(recordName: modified.userRecordName)
            self.modificationDate = Date(timeIntervalSince1970: Double(modified.timestamp) / 1000)
        }

        // Enumerate Fields
        if let fields = recordDictionary[CKRecordDictionary.fields] as? [String: [String: Any]] {
            for (key, fieldValue) in fields  {
                let value = CKRecord.getValue(forRecordField: fieldValue)
                values[key] = value
            }
        }

        if let parentReferenceDictionary = recordDictionary["parent"] as? [String: Any], let recordName = parentReferenceDictionary["parent"] as? String {

            let recordID = CKRecordID(recordName: recordName, zoneID: zoneID)
            let reference = CKReference(recordID: recordID, action: .none)
            parent = reference
        }
    }

    public required init?(coder: NSCoder) {
        recordType = coder.decodeObject(of: NSString.self, forKey: "RecordType")! as String
        recordID = coder.decodeObject(of: CKRecordID.self, forKey: "RecordID")!
        recordChangeTag = coder.decodeObject(of: NSString.self, forKey: "ETag") as String?
        creatorUserRecordID = coder.decodeObject(of: CKRecordID.self, forKey: "CreatorUserRecordID")
        creationDate = coder.decodeObject(of: NSDate.self, forKey: "RecordCtime")! as Date
        lastModifiedUserRecordID = coder.decodeObject(of: CKRecordID.self, forKey: "LastModifiedUserRecordID")
        modificationDate = coder.decodeObject(of: NSDate.self, forKey: "RecordMtime") as Date?
        parent = coder.decodeObject(of: CKReference.self, forKey: "ParentReference")
        // TODO: changed keys set
    }

    public func encode(with coder: NSCoder) {
        coder.encode(recordType, forKey: "RecordType")
        coder.encode(recordID, forKey: "RecordID")
        coder.encode(recordChangeTag, forKey: "ETag")
        coder.encode(creatorUserRecordID, forKey: "CreatorUserRecordID")
        coder.encode(creationDate, forKey: "RecordCtime")
        coder.encode(lastModifiedUserRecordID, forKey: "LastModifiedUserRecordID")
        coder.encode(modificationDate, forKey: "RecordMtime")
        coder.encode(parent, forKey: "ParentReference")
        // TODO: changed keys set
    }

    public static var supportsSecureCoding: Bool {
        return true
    }

    public func encodeSystemFields(with coder: NSCoder) {
        encode(with: coder)
    }
}

struct CKRecordDictionary {
    static let recordName = "recordName"
    static let recordType = "recordType"
    static let recordChangeTag = "recordChangeTag"
    static let fields = "fields"
    static let zoneID = "zoneID"
    static let modified = "modified"
    static let created = "created"
}

struct CKRecordFieldDictionary {
    static let value = "value"
    static let type = "type"
}

struct CKValueType {
    static let string = "STRING"
    static let data = "BYTES"
}

struct CKRecordLog {
    let timestamp: UInt64 // milliseconds
    let userRecordName: String
    let deviceID: String

    init?(dictionary: [String: Any]) {
        guard let timestamp = (dictionary["timestamp"] as? NSNumber)?.uint64Value, let userRecordName = dictionary["userRecordName"] as? String, let deviceID =  dictionary["deviceID"] as? String else {
            return nil
        }

        self.timestamp = timestamp
        self.userRecordName = userRecordName
        self.deviceID = deviceID
    }
}

extension CKRecord {

    func fieldsDictionary(forKeys keys: [String]) -> [String: Any] {

        var fieldsDictionary: [String: Any] = [:]

        for key in keys {
            if let value = object(forKey: key) {
                fieldsDictionary[key] = value.recordFieldDictionary.bridge() as NSDictionary
            }
        }

        CloudKit.debugPrint(fieldsDictionary)


        return fieldsDictionary

    }

    var dictionary: [String: Any] {

        // Add Fields
        var fieldsDictionary: [String: Any] = [:]
        for (key, value) in values {
            fieldsDictionary[key] = value.recordFieldDictionary.bridge() as NSDictionary
        }

        var recordDictionary: [String: Any] = [
        "fields": fieldsDictionary.bridge() as NSDictionary,
        "recordType": recordType.bridge(),
        "recordName": recordID.recordName.bridge()
        ]

        if let parent = parent {
            recordDictionary["createShortGUID"] = NSNumber(value: 1)
            recordDictionary["parent"] = ["recordName": parent.recordID.recordName.bridge()].bridge()
        }

        return recordDictionary
    }

    static func recordValue(forValue value: Any) -> CKRecordValue {
        switch value {
        case let number as NSNumber:
           return number

        default:
            fatalError("Not Supported")
        }
    }

    static func process(number: NSNumber, type: String) -> CKRecordValue {
        switch(type) {
        case "TIMESTAMP":
            return NSDate(timeIntervalSince1970: number.doubleValue / 1000)
        default:
            return number
        }
    }

    static func getValue(forRecordField field: [String: Any]) -> CKRecordValue? {
        if  let value = field[CKRecordFieldDictionary.value],
            let type = field[CKRecordFieldDictionary.type] as? String {

            switch value {
            case let number as NSNumber:
                return process(number: number, type: type)

            case let intValue as Int:
                let number = NSNumber(value: intValue)
                return process(number: number, type: type)

            case let doubleValue as Double:
                let number = NSNumber(value: doubleValue)
                return process(number: number, type: type)

            case let dictionary as [String: Any]:
                switch type {

                case "LOCATION":
                    let latitude = (dictionary["latitude"] as! NSNumber).doubleValue
                    let longitude = (dictionary["longitude"] as! NSNumber).doubleValue

                    return CKLocation(latitude: latitude, longitude: longitude)
                case "ASSETID":
                    // size
                    // downloadURL
                    // fileChecksum
                    return CKAsset(dictionary: dictionary)
                case "REFERENCE":
                    return CKReference(dictionary: dictionary)
                default:
                    fatalError("Type not supported")
                }

            case let boolean as Bool:
                return NSNumber(booleanLiteral: boolean)

            case let string as String:
                switch type {
                case CKValueType.string:
                    return string
                case CKValueType.data:
                    #if os(Linux)
                        return NSData(base64Encoded: string,
                               options: [])
                    #else
                        return NSData(base64Encoded: string)
                    #endif
                default:
                    return string
                }

            case let array as [Any]:
                switch type {
                case "INT64_LIST":
                    let numberArray =  array as! [NSNumber]
                   return NSArray(array: numberArray)
                case "STRING_LIST":
                   // let stringArray =  array.bridge() as! [String]
                    return array.bridge()
                case "TIMESTAMP_LIST":
                    let dateArray = (array as! [NSNumber]).map({ (timestamp) -> NSDate in
                        return  NSDate(timeIntervalSince1970: timestamp.doubleValue / 1000)
                    })
                    return NSArray(array: dateArray)

                default:
                    fatalError("List type of \(type) not supported")
                }

            default:
                return nil
            }
        } else {
            return nil
        }
    }



}

extension NSString : CKRecordValue {
    public var recordFieldDictionary: [String : Any] {
        return ["value": self, "type":"STRING".bridge()]
    }
}

extension String : CKRecordValue {
    public var recordFieldDictionary: [String : Any] {
        return ["value": self.bridge(), "type":"STRING".bridge()]
    }
}


extension NSNumber : CKRecordValue {}

extension NSArray : CKRecordValue {}

extension Int : CKNumberValueType {}

extension Double: CKNumberValueType {}

extension Float: CKNumberValueType {}

extension UInt: CKNumberValueType {}

extension NSDate : CKRecordValue {
    public var recordFieldDictionary: [String : Any] {
        return ["value": NSNumber(value: UInt64(self.timeIntervalSince1970 * 1000)), "type":"TIMESTAMP".bridge()]
    }
}

extension Date : CKRecordValue {
    public var recordFieldDictionary: [String : Any] {
        return ["value": NSNumber(value: UInt64(self.timeIntervalSince1970 * 1000)), "type":"TIMESTAMP".bridge()]
    }
}

extension NSData : CKRecordValue {}

extension CKAsset: CKRecordValue {}

extension CKReference: CKRecordValue {
    public var recordFieldDictionary: [String: Any] {
        return ["value": self.dictionary.bridge() as Any, "type": "REFERENCE".bridge()]
    }
}

extension CKLocation: CKRecordValue {
    public var recordFieldDictionary: [String: Any] {

        return ["value": self.dictionary.bridge() as Any, "type": "LOCATION".bridge()]
    }
}

extension CKLocationType {
    public var recordFieldDictionary: [String: Any] {
        return ["value": self.dictionary.bridge() as Any, "type": "LOCATION".bridge()]
    }
}
