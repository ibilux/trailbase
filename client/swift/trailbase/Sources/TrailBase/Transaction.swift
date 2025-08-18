swift
import Foundation

public struct Operation: Codable {
    public var create: CreateOperation? = nil
    public var update: UpdateOperation? = nil
    public var delete: DeleteOperation? = nil

    private enum CodingKeys: String, CodingKey {
        case create = "Create"
        case update = "Update"
        case delete = "Delete"
    }
}

public struct CreateOperation: Codable {
    public var apiName: String = ""
    public var record: [String: AnyCodable] = [:]

    private enum CodingKeys: String, CodingKey {
        case apiName = "api_name"
        case record = "record"
    }
}

public struct UpdateOperation: Codable {
    public var apiName: String = ""
    public var id: String = ""
    public var record: [String: AnyCodable] = [:]

    private enum CodingKeys: String, CodingKey {
        case apiName = "api_name"
        case id = "id"
        case record = "record"
    }
}

public struct DeleteOperation: Codable {
    public var apiName: String = ""
    public var recordId: String = ""

    private enum CodingKeys: String, CodingKey {
        case apiName = "api_name"
        case recordId = "record_id"
    }
}

public struct TransactionRequest: Codable {
    public var operations: [Operation] = []

    private enum CodingKeys: String, CodingKey {
        case operations = "operations"
    }
}

public struct TransactionResponse: Codable {
    public var ids: [String] = []

    private enum CodingKeys: String, CodingKey {
        case ids = "ids"
    }
}

public class TransactionBatch {
    private let client: Client
    private var operations: [Operation] = []

    init(client: Client) {
        self.client = client
    }

    public func api(_ apiName: String) -> ApiBatch {
        return ApiBatch(batch: self, apiName: apiName)
    }

    public func send() async throws -> [String] {
        let request = TransactionRequest(operations: operations)
        let body = try JSONEncoder().encode(request)

        let (_, data) = try await client.fetch(
            path: "/api/transactions/v1/execute",
            method: "POST",
            body: body
        )

        let response = try JSONDecoder().decode(TransactionResponse.self, from: data)
        return response.ids
    }

    internal func addOperation(_ operation: Operation) {
        operations.append(operation)
    }
}

public class ApiBatch {
    private let batch: TransactionBatch
    private let apiName: String

    init(batch: TransactionBatch, apiName: String) {
        self.batch = batch
        self.apiName = apiName
    }

    public func create(record: [String: AnyCodable]) -> TransactionBatch {
        batch.addOperation(Operation(create: CreateOperation(apiName: apiName, record: record)))
        return batch
    }

    public func update(recordId: String, record: [String: AnyCodable]) -> TransactionBatch {
        batch.addOperation(Operation(update: UpdateOperation(apiName: apiName, id: recordId, record: record)))
        return batch
    }

    public func delete(recordId: String) -> TransactionBatch {
        batch.addOperation(Operation(delete: DeleteOperation(apiName: apiName, recordId: recordId)))
        return batch
    }
}

// Helper for allowing [String: Any] in Codable
public struct AnyCodable: Codable {
    public let value: Any

    public init<T>(_ value: T?) {
        self.value = value ?? () // Use a sentinel value for nil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = () // Sentinel value for nil
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            self.value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if value is () {
            try container.encodeNil()
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let string = value as? String {
            try container.encode(string)
        } else if let array = value as? [Any] {
            try container.encode(array.map(AnyCodable.init))
        } else if let dictionary = value as? [String: Any] {
            try container.encode(dictionary.mapValues(AnyCodable.init))
        } else {
            let context = EncodingError.Context(codingPath: container.codingPath, debugDescription: "AnyCodable value cannot be encoded")
            throw EncodingError.invalidValue(value, context)
        }
    }
}