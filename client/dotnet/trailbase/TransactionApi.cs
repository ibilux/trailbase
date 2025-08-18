using System;  
using System.Collections.Generic;  
using System.Net.Http;  
using System.Text;  
using System.Text.Json;  
using System.Threading.Tasks;  
  
namespace TrailBase.Client  
{
    public class Operation  
    {  
        public CreateOperation? Create { get; set; }  
        public UpdateOperation? Update { get; set; }  
        public DeleteOperation? Delete { get; set; }  
    }  
  
    public class CreateOperation  
    {  
        public string ApiName { get; set; } = string.Empty;  
        public Dictionary<string, object> Record { get; set; } = new();  
    }  
  
    public class UpdateOperation  
    {  
        public string ApiName { get; set; } = string.Empty;  
        public string Id { get; set; } = string.Empty;  
        public Dictionary<string, object> Record { get; set; } = new();  
    }  
  
    public class DeleteOperation  
    {  
        public string ApiName { get; set; } = string.Empty;  
        public string RecordId { get; set; } = string.Empty;  
    }  
  
    public class TransactionRequest  
    {  
        public List<Operation> Operations { get; set; } = new();  
    }  
  
    public class TransactionResponse  
    {  
        public List<string> Ids { get; set; } = new();  
    }  
  
    public interface ITransactionBatch  
    {  
        IApiBatch Api(string apiName);  
        Task<List<string>> SendAsync();  
    }  
  
    public interface IApiBatch  
    {  
        ITransactionBatch Create(Dictionary<string, object> record);  
        ITransactionBatch Update(string recordId, Dictionary<string, object> record);  
        ITransactionBatch Delete(string recordId);  
    }  
  
    public class TransactionBatch : ITransactionBatch  
    {  
        private readonly Client _client;  
        private readonly List<Operation> _operations = new();  
  
        public TransactionBatch(Client client)  
        {  
            _client = client;  
        }  
  
        public IApiBatch Api(string apiName)  
        {  
            return new ApiBatch(this, apiName);  
        }  
  
        public async Task<List<string>> SendAsync()  
        {  
            var request = new TransactionRequest { Operations = _operations };  
            var response = await _client.Fetch(  
                "/api/transactions/v1/execute",  
                HttpMethod.Post,  
                JsonContent.Create(request),  
                null  
            );  
  
            string json = await response.Content.ReadAsStringAsync();  
            var result = JsonSerializer.Deserialize<TransactionResponse>(json);  
              
            return result?.Ids ?? new List<string>();  
        }  
  
        internal void AddOperation(Operation operation)  
        {  
            _operations.Add(operation);  
        }  
    }  
  
    public class ApiBatch : IApiBatch  
    {  
        private readonly TransactionBatch _batch;  
        private readonly string _apiName;  
  
        public ApiBatch(TransactionBatch batch, string apiName)  
        {  
            _batch = batch;  
            _apiName = apiName;  
        }  
  
        public ITransactionBatch Create(Dictionary<string, object> record)  
        {  
            _batch.AddOperation(new Operation  
            {  
                Create = new CreateOperation  
                {  
                    ApiName = _apiName,  
                    Record = record  
                }  
            });  
            return _batch;  
        }  
  
        public ITransactionBatch Update(string recordId, Dictionary<string, object> record)  
        {  
            _batch.AddOperation(new Operation  
            {  
                Update = new UpdateOperation  
                {  
                    ApiName = _apiName,  
                    Id = recordId,  
                    Record = record  
                }  
            });  
            return _batch;  
        }  
  
        public ITransactionBatch Delete(string recordId)  
        {  
            _batch.AddOperation(new Operation  
            {  
                Delete = new DeleteOperation  
                {  
                    ApiName = _apiName,  
                    RecordId = recordId  
                }  
            });  
            return _batch;  
        }  
    }  
}
