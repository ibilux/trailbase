package trailbase

import (
	"encoding/json"
	"fmt"
	"net/http"
)

type Operation struct {
	Type     string                 `json:"-"`
	ApiName  string                 `json:"api_name"`
	RecordID string                 `json:"record_id,omitempty"`
	Value    map[string]interface{} `json:"value,omitempty"`
}

func (o Operation) MarshalJSON() ([]byte, error) {
	var wrapper struct {
		Create *struct {
			ApiName string                 `json:"api_name"`
			Value   map[string]interface{} `json:"value"`
		} `json:"Create,omitempty"`
		Update *struct {
			ApiName  string                 `json:"api_name"`
			RecordID string                 `json:"record_id"`
			Value    map[string]interface{} `json:"value"`
		} `json:"Update,omitempty"`
		Delete *struct {
			ApiName  string `json:"api_name"`
			RecordID string `json:"record_id"`
		} `json:"Delete,omitempty"`
	}

	switch o.Type {
	case "Create":
		wrapper.Create = &struct {
			ApiName string                 `json:"api_name"`
			Value   map[string]interface{} `json:"value"`
		}{
			ApiName: o.ApiName,
			Value:   o.Value,
		}
	case "Update":
		wrapper.Update = &struct {
			ApiName  string                 `json:"api_name"`
			RecordID string                 `json:"record_id"`
			Value    map[string]interface{} `json:"value"`
		}{
			ApiName:  o.ApiName,
			RecordID: o.RecordID,
			Value:    o.Value,
		}
	case "Delete":
		wrapper.Delete = &struct {
			ApiName  string `json:"api_name"`
			RecordID string `json:"record_id"`
		}{
			ApiName:  o.ApiName,
			RecordID: o.RecordID,
		}
	}

	return json.Marshal(wrapper)
}

type TransactionRequest struct {
	Operations []Operation `json:"operations"`
}

type TransactionResponse struct {
	IDs []string `json:"ids"`
}

type TransactionBatch struct {
	client     Client
	operations []Operation
}

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

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("unexpected status code: %d", resp.StatusCode)
	}

	var response TransactionResponse
	decoder := json.NewDecoder(resp.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&response); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	if response.IDs == nil {
		response.IDs = []string{} // Ensure non-nil slice
	}

	return response.IDs, nil
}

func (tb *TransactionBatch) addOperation(op Operation) {
	tb.operations = append(tb.operations, op)
}

func (ab *ApiBatch) Create(value map[string]interface{}) *TransactionBatch {
	ab.batch.addOperation(Operation{
		Type:    "Create",
		ApiName: ab.apiName,
		Value:   value,
	})
	return ab.batch
}

func (ab *ApiBatch) Update(recordID string, value map[string]interface{}) *TransactionBatch {
	ab.batch.addOperation(Operation{
		Type:     "Update",
		ApiName:  ab.apiName,
		RecordID: recordID,
		Value:    value,
	})
	return ab.batch
}

func (ab *ApiBatch) Delete(recordID string) *TransactionBatch {
	ab.batch.addOperation(Operation{
		Type:     "Delete",
		ApiName:  ab.apiName,
		RecordID: recordID,
	})
	return ab.batch
}
