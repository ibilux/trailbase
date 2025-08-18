package trailbase  
  
import (  
    "encoding/json"  
    "fmt"  
)  
  
// Operation types matching your JS implementation  
type Operation struct {  
    Create *CreateOperation `json:"Create,omitempty"`  
    Update *UpdateOperation `json:"Update,omitempty"`  
    Delete *DeleteOperation `json:"Delete,omitempty"`  
}  
  
type CreateOperation struct {  
    ApiName string                 `json:"api_name"`  
    Record  map[string]interface{} `json:"record"`  
}  
  
type UpdateOperation struct {  
    ApiName string                 `json:"api_name"`  
    ID      string                 `json:"id"`  
    Record  map[string]interface{} `json:"record"`  
}  
  
type DeleteOperation struct {  
    ApiName  string `json:"api_name"`  
    RecordID string `json:"record_id"`  
}  
  
type TransactionRequest struct {  
    Operations []Operation `json:"operations"`  
}  
  
type TransactionResponse struct {  
    IDs []string `json:"ids"`  
}  
  
// TransactionBatch for building batched operations  
type TransactionBatch struct {  
    client     Client  
    operations []Operation  
}  
  
// ApiBatch for API-specific operations  
type ApiBatch struct {  
    batch   *TransactionBatch  
    apiName string  
}  
  
func (tb *TransactionBatch) API(apiName string) *ApiBatch {  
    return &ApiBatch{  
        batch:   tb,  
        apiName: apiName,  
    }  
}  
  
func (tb *TransactionBatch) Send() ([]string, error) {  
    reqBody := TransactionRequest{  
        Operations: tb.operations,  
    }  
      
    jsonData, err := json.Marshal(reqBody)  
    if err != nil {  
        return nil, fmt.Errorf("failed to marshal request: %w", err)  
    }  
      
    resp, err := tb.client.do("POST", "/api/transactions/v1/execute", jsonData, []QueryParam{})  
    if err != nil {  
        return nil, fmt.Errorf("failed to send request: %w", err)  
    }  
    defer resp.Body.Close()  
      
    var response TransactionResponse  
    if err := json.NewDecoder(resp.Body).Decode(&response); err != nil {  
        return nil, fmt.Errorf("failed to decode response: %w", err)  
    }  
      
    return response.IDs, nil  
}  
  
func (tb *TransactionBatch) addOperation(op Operation) {  
    tb.operations = append(tb.operations, op)  
}  
  
func (ab *ApiBatch) Create(record map[string]interface{}) *TransactionBatch {  
    ab.batch.addOperation(Operation{  
        Create: &CreateOperation{  
            ApiName: ab.apiName,  
            Record:  record,  
        },  
    })  
    return ab.batch  
}  
  
func (ab *ApiBatch) Update(recordID string, record map[string]interface{}) *TransactionBatch {  
    ab.batch.addOperation(Operation{  
        Update: &UpdateOperation{  
            ApiName: ab.apiName,  
            ID:      recordID,  
            Record:  record,  
        },  
    })  
    return ab.batch  
}  
  
func (ab *ApiBatch) Delete(recordID string) *TransactionBatch {  
    ab.batch.addOperation(Operation{  
        Delete: &DeleteOperation{  
            ApiName:  ab.apiName,  
            RecordID: recordID,  
        },  
    })  
    return ab.batch  
}
