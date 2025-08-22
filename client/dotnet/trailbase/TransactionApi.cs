using System;
using System.Collections.Generic;
using System.Diagnostics.CodeAnalysis;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;

namespace TrailBase.Client {
  [JsonConverter(typeof(OperationJsonConverter))]
  public abstract class Operation {
    [JsonPropertyName("api_name")]
    public string ApiName { get; set; } = string.Empty;

    public static Operation Create(string apiName, Dictionary<string, object> value)
        => new CreateOperation { ApiName = apiName, Value = value };

    public static Operation Update(string apiName, string recordId, Dictionary<string, object> value)
        => new UpdateOperation { ApiName = apiName, RecordId = recordId, Value = value };

    public static Operation Delete(string apiName, string recordId)
        => new DeleteOperation { ApiName = apiName, RecordId = recordId };
  }

  public class CreateOperation : Operation {
    [JsonPropertyName("value")]
    public Dictionary<string, object> Value { get; set; } = new();
  }

  public class UpdateOperation : Operation {
    [JsonPropertyName("record_id")]
    public string RecordId { get; set; } = string.Empty;

    [JsonPropertyName("value")]
    public Dictionary<string, object> Value { get; set; } = new();
  }

  public class DeleteOperation : Operation {
    [JsonPropertyName("record_id")]
    public string RecordId { get; set; } = string.Empty;
  }

  public class OperationJsonConverter : JsonConverter<Operation> {
    [RequiresDynamicCode()]
    [RequiresUnreferencedCode()]
    public override Operation? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) {
      if (reader.TokenType != JsonTokenType.StartObject)
        throw new JsonException();

      using (var doc = JsonDocument.ParseValue(ref reader)) {
        var root = doc.RootElement;

        if (root.TryGetProperty("Create", out var createElem)) {
          return JsonSerializer.Deserialize<CreateOperation>(createElem.GetRawText(), options);
        }
        else if (root.TryGetProperty("Update", out var updateElem)) {
          return JsonSerializer.Deserialize<UpdateOperation>(updateElem.GetRawText(), options);
        }
        else if (root.TryGetProperty("Delete", out var deleteElem)) {
          return JsonSerializer.Deserialize<DeleteOperation>(deleteElem.GetRawText(), options);
        }

        throw new JsonException("Unknown operation type");
      }
    }

    [RequiresUnreferencedCode()]
    [RequiresDynamicCode()]
    [RequiresDynamicCode()]
    public override void Write(Utf8JsonWriter writer, Operation value, JsonSerializerOptions options) {
      writer.WriteStartObject();

      switch (value) {
        case CreateOperation create:
          writer.WritePropertyName("Create");
          writer.WriteStartObject();
          writer.WriteString("api_name", create.ApiName);
          writer.WritePropertyName("value");
          JsonSerializer.Serialize(writer, create.Value, options);
          writer.WriteEndObject();
          break;

        case UpdateOperation update:
          writer.WritePropertyName("Update");
          writer.WriteStartObject();
          writer.WriteString("api_name", update.ApiName);
          writer.WriteString("record_id", update.RecordId);
          writer.WritePropertyName("value");
          JsonSerializer.Serialize(writer, update.Value, options);
          writer.WriteEndObject();
          break;

        case DeleteOperation delete:
          writer.WritePropertyName("Delete");
          writer.WriteStartObject();
          writer.WriteString("api_name", delete.ApiName);
          writer.WriteString("record_id", delete.RecordId);
          writer.WriteEndObject();
          break;

        default:
          throw new JsonException($"Unknown operation type: {value.GetType()}");
      }

      writer.WriteEndObject();
    }
  }

  public class TransactionRequest {
    [System.Text.Json.Serialization.JsonPropertyName("operations")]
    public List<Operation> Operations { get; set; } = new();
  }

  public class TransactionResponse {
    [System.Text.Json.Serialization.JsonPropertyName("ids")]
    public List<string> Ids { get; set; } = new();
  }

  public interface ITransactionBatch {
    IApiBatch Api(string apiName);
    Task<List<string>> SendAsync();
  }

  public interface IApiBatch {
    ITransactionBatch Create(Dictionary<string, object> record);
    ITransactionBatch Update(RecordId recordId, Dictionary<string, object> record);
    ITransactionBatch Delete(RecordId recordId);
  }

  public class TransactionBatch : ITransactionBatch {
    private readonly Client _client;
    private readonly List<Operation> _operations = new();

    public TransactionBatch(Client client) {
      _client = client;
    }

    public IApiBatch Api(string apiName) {
      return new ApiBatch(this, apiName);
    }

    [RequiresUnreferencedCode()]
    [RequiresDynamicCode()]
    [RequiresDynamicCode()]
    public async Task<List<string>> SendAsync() {
      var request = new TransactionRequest { Operations = _operations };
      var response = await _client.Fetch(
          "api/transaction/v1/execute",
          HttpMethod.Post,
          JsonContent.Create(request),
          null
      );

      string json = await response.Content.ReadAsStringAsync();
      var result = JsonSerializer.Deserialize<TransactionResponse>(json);

      return result?.Ids ?? new List<string>();
    }

    internal void AddOperation(Operation operation) {
      _operations.Add(operation);
    }
  }

  public class ApiBatch : IApiBatch {
    private readonly TransactionBatch _batch;
    private readonly string _apiName;

    public ApiBatch(TransactionBatch batch, string apiName) {
      _batch = batch;
      _apiName = apiName;
    }

    public ITransactionBatch Create(Dictionary<string, object> value) {
      _batch.AddOperation(Operation.Create(_apiName, value));
      return _batch;
    }

    public ITransactionBatch Update(RecordId recordId, Dictionary<string, object> value) {
      _batch.AddOperation(Operation.Update(_apiName, recordId.ToString(), value));
      return _batch;
    }

    public ITransactionBatch Delete(RecordId recordId) {
      _batch.AddOperation(Operation.Delete(_apiName, recordId.ToString()));
      return _batch;
    }
  }
}
