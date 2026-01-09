# Event-Driven Architecture Implementation Examples

This document provides complete Go implementation examples for common event-driven architecture scenarios following the platform's conventions.

## 1. Complete Order Processing Saga

This example shows a complete order processing workflow using saga pattern with proper compensation.

### Domain Events

```go
package event

import (
	"time"
	"github.com/google/uuid"
)

// Shopping Cart Events
type CartFinalized struct {
	CartID      string    `json:"cart_id"`
	ClientID    string    `json:"client_id"`
	ProductItems []ProductItem `json:"product_items"`
	TotalPrice  float64   `json:"total_price"`
	ConfirmedAt time.Time `json:"confirmed_at"`
}

// Order Events
type OrderInitialized struct {
	OrderID      string    `json:"order_id"`
	CartID       string    `json:"cart_id"`
	ClientID     string    `json:"client_id"`
	ProductItems []ProductItem `json:"product_items"`
	TotalPrice   float64   `json:"total_price"`
	InitializedAt time.Time `json:"initialized_at"`
}

type OrderCancelled struct {
	OrderID     string    `json:"order_id"`
	Reason      string    `json:"reason"`
	CancelledAt time.Time `json:"cancelled_at"`
}

type OrderCompleted struct {
	OrderID    string    `json:"order_id"`
	CompletedAt time.Time `json:"completed_at"`
}

// Payment Events
type PaymentRequested struct {
	PaymentID string  `json:"payment_id"`
	OrderID   string  `json:"order_id"`
	Amount    float64 `json:"amount"`
	RequestedAt time.Time `json:"requested_at"`
}

type PaymentCompleted struct {
	PaymentID   string    `json:"payment_id"`
	OrderID     string    `json:"order_id"`
	Amount      float64   `json:"amount"`
	CompletedAt time.Time `json:"completed_at"`
}

type PaymentFailed struct {
	PaymentID string    `json:"payment_id"`
	OrderID   string    `json:"order_id"`
	Amount    float64   `json:"amount"`
	Error     string    `json:"error"`
	FailedAt  time.Time `json:"failed_at"`
}

type PaymentDiscarded struct {
	PaymentID   string    `json:"payment_id"`
	OrderID     string    `json:"order_id"`
	Amount      float64   `json:"amount"`
	DiscardedAt time.Time `json:"discarded_at"`
}

// Shipment Events
type ShipmentRequested struct {
	ShipmentID   string       `json:"shipment_id"`
	OrderID      string       `json:"order_id"`
	ProductItems []ProductItem `json:"product_items"`
	RequestedAt  time.Time    `json:"requested_at"`
}

type ShipmentSent struct {
	ShipmentID string    `json:"shipment_id"`
	OrderID   string    `json:"order_id"`
	SentAt    time.Time `json:"sent_at"`
}

type ShipmentFailed struct {
	ShipmentID string    `json:"shipment_id"`
	OrderID   string    `json:"order_id"`
	Error     string    `json:"error"`
	FailedAt  time.Time `json:"failed_at"`
}

type ProductItem struct {
	ProductID string `json:"product_id"`
	Quantity  int    `json:"quantity"`
	UnitPrice float64 `json:"unit_price"`
}
```

### Commands

```go
package command

import (
	"github.com/yourproject/internal/domain/event"
)

// Order Commands
type InitializeOrder struct {
	CartID       string               `json:"cart_id"`
	OrderID      string               `json:"order_id"`
	ClientID     string               `json:"client_id"`
	ProductItems []event.ProductItem  `json:"product_items"`
	TotalPrice   float64              `json:"total_price"`
}

type CancelOrder struct {
	OrderID string `json:"order_id"`
	Reason  string `json:"reason"`
}

type CompleteOrder struct {
	OrderID string `json:"order_id"`
}

// Payment Commands
type RequestPayment struct {
	PaymentID string  `json:"payment_id"`
	OrderID   string  `json:"order_id"`
	Amount    float64 `json:"amount"`
}

type DiscardPayment struct {
	PaymentID string `json:"payment_id"`
	OrderID   string `json:"order_id"`
}

// Shipment Commands
type RequestShipment struct {
	ShipmentID   string               `json:"shipment_id"`
	OrderID      string               `json:"order_id"`
	ProductItems []event.ProductItem  `json:"product_items"`
}
```

### Saga Implementation

```go
package saga

import (
	"context"
	
	"github.com/google/uuid"
	"github.com/yourproject/internal/domain/command"
	"github.com/yourproject/internal/domain/event"
)

// OrderSaga handles the complete order processing workflow
type OrderSaga struct {
	commandBus command.Bus
}

func NewOrderSaga(commandBus command.Bus) *OrderSaga {
	return &OrderSaga{
		commandBus: commandBus,
	}
}

// Happy path handlers
func (s *OrderSaga) HandleCartFinalized(ctx context.Context, evt event.CartFinalized) error {
	cmd := command.InitializeOrder{
		CartID:       evt.CartID,
		OrderID:      uuid.New().String(),
		ClientID:     evt.ClientID,
		ProductItems: evt.ProductItems,
		TotalPrice:   evt.TotalPrice,
	}
	
	return s.commandBus.Send(ctx, cmd)
}

func (s *OrderSaga) HandleOrderInitialized(ctx context.Context, evt event.OrderInitialized) error {
	cmd := command.RequestPayment{
		PaymentID: uuid.New().String(),
		OrderID:   evt.OrderID,
		Amount:    evt.TotalPrice,
	}
	
	return s.commandBus.Send(ctx, cmd)
}

func (s *OrderSaga) HandlePaymentCompleted(ctx context.Context, evt event.PaymentCompleted) error {
	cmd := command.RequestShipment{
		ShipmentID: uuid.New().String(),
		OrderID:    evt.OrderID,
	}
	
	return s.commandBus.Send(ctx, cmd)
}

func (s *OrderSaga) HandleShipmentSent(ctx context.Context, evt event.ShipmentSent) error {
	cmd := command.CompleteOrder{
		OrderID: evt.OrderID,
	}
	
	return s.commandBus.Send(ctx, cmd)
}

// Compensation handlers
func (s *OrderSaga) HandlePaymentFailed(ctx context.Context, evt event.PaymentFailed) error {
	cmd := command.CancelOrder{
		OrderID: evt.OrderID,
		Reason:  "Payment failed: " + evt.Error,
	}
	
	return s.commandBus.Send(ctx, cmd)
}

func (s *OrderSaga) HandleShipmentFailed(ctx context.Context, evt event.ShipmentFailed) error {
	cmd := command.DiscardPayment{
		PaymentID: "", // This should be stored in saga state or event
		OrderID:   evt.OrderID,
	}
	
	return s.commandBus.Send(ctx, cmd)
}

func (s *OrderSaga) HandleOrderCancelled(ctx context.Context, evt event.OrderCancelled) error {
	// If order is cancelled due to shipment failure, discard payment
	if evt.Reason == "Shipment failed" {
		// In a real implementation, you'd have the payment ID
		// This could be stored in the order aggregate or in saga state
		cmd := command.DiscardPayment{
			PaymentID: "", // Get from order aggregate
			OrderID:   evt.OrderID,
		}
		
		return s.commandBus.Send(ctx, cmd)
	}
	
	return nil
}
```

### Saga Registration

```go
package handlers

import (
	"github.com/yourproject/internal/domain/event"
	"github.com/yourproject/internal/saga"
)

type SagaEventHandler struct {
	orderSaga *saga.OrderSaga
}

func NewSagaEventHandler(orderSaga *saga.OrderSaga) *SagaEventHandler {
	return &SagaEventHandler{
		orderSaga: orderSaga,
	}
}

func (h *SagaEventHandler) RegisterHandlers(eventHandler event.Handler) {
	// Happy path
	eventHandler.Register(event.CartFinalized{}, h.orderSaga.HandleCartFinalized)
	eventHandler.Register(event.OrderInitialized{}, h.orderSaga.HandleOrderInitialized)
	eventHandler.Register(event.PaymentCompleted{}, h.orderSaga.HandlePaymentCompleted)
	eventHandler.Register(event.ShipmentSent{}, h.orderSaga.HandleShipmentSent)
	
	// Compensation path
	eventHandler.Register(event.PaymentFailed{}, h.orderSaga.HandlePaymentFailed)
	eventHandler.Register(event.ShipmentFailed{}, h.orderSaga.HandleShipmentFailed)
	eventHandler.Register(event.OrderCancelled{}, h.orderSaga.HandleOrderCancelled)
}
```

## 2. Process Manager for Complex Workflow

This example shows a process manager for a hotel group checkout scenario with state management.

### Process Manager Implementation

```go
package processmanager

import (
	"context"
	"sync"
	"time"
	
	"github.com/google/uuid"
	"github.com/yourproject/internal/domain/command"
	"github.com/yourproject/internal/domain/event"
)

type ProcessState int

const (
	StateStarted ProcessState = iota
	StateCheckingOut
	StateCompleted
	StateFailed
)

type GroupCheckoutProcess struct {
	ID               string
	GuestStayIDs     []string
	CompletedCount   int
	FailedCount      int
	State            ProcessState
	StartedAt        time.Time
	LastActivityAt   time.Time
	mutex           sync.RWMutex
}

func NewGroupCheckoutProcess(guestCheckoutID string, guestStayIDs []string) *GroupCheckoutProcess {
	return &GroupCheckoutProcess{
		ID:            guestCheckoutID,
		GuestStayIDs:  guestStayIDs,
		State:         StateStarted,
		StartedAt:     time.Now(),
		LastActivityAt: time.Now(),
	}
}

func (p *GroupCheckoutProcess) RecordCompletion() {
	p.mutex.Lock()
	defer p.mutex.Unlock()
	
	p.CompletedCount++
	p.LastActivityAt = time.Now()
	
	if p.CompletedCount+len(p.FailedCount) >= len(p.GuestStayIDs) {
		if p.FailedCount == 0 {
			p.State = StateCompleted
		} else {
			p.State = StateFailed
		}
	}
}

func (p *GroupCheckoutProcess) RecordFailure() {
	p.mutex.Lock()
	defer p.mutex.Unlock()
	
	p.FailedCount++
	p.LastActivityAt = time.Now()
	p.State = StateFailed
}

type GroupCheckoutProcessManager struct {
	commandBus command.Bus
	processes map[string]*GroupCheckoutProcess
	mutex     sync.RWMutex
}

func NewGroupCheckoutProcessManager(commandBus command.Bus) *GroupCheckoutProcessManager {
	return &GroupCheckoutProcessManager{
		commandBus: commandBus,
		processes:  make(map[string]*GroupCheckoutProcess),
	}
}

func (pm *GroupCheckoutProcessManager) HandleGroupCheckoutInitiated(
	ctx context.Context,
	evt event.GroupCheckoutInitiated,
) error {
	pm.mutex.Lock()
	defer pm.mutex.Unlock()
	
	process := NewGroupCheckoutProcess(evt.GroupCheckoutID, evt.GuestStayIDs)
	pm.processes[evt.GroupCheckoutID] = process
	
	// Send checkout commands for all guests
	for _, guestStayID := range evt.GuestStayIDs {
		cmd := command.CheckoutGuestAccount{
			GuestStayID:     guestStayID,
			GroupCheckoutID: evt.GroupCheckoutID,
		}
		
		if err := pm.commandBus.Send(ctx, cmd); err != nil {
			return err
		}
	}
	
	return nil
}

func (pm *GroupCheckoutProcessManager) HandleGuestCheckoutCompleted(
	ctx context.Context,
	evt event.GuestCheckoutCompleted,
) error {
	process, err := pm.getOrCreateProcess(evt.GroupCheckoutID)
	if err != nil {
		return err
	}
	
	process.RecordCompletion()
	
	if process.State == StateCompleted {
		cmd := command.CompleteGroupCheckout{
			GroupCheckoutID: evt.GroupCheckoutID,
		}
		return pm.commandBus.Send(ctx, cmd)
	}
	
	return nil
}

func (pm *GroupCheckoutProcessManager) HandleGuestCheckoutFailed(
	ctx context.Context,
	evt event.GuestCheckoutFailed,
) error {
	process, err := pm.getOrCreateProcess(evt.GroupCheckoutID)
	if err != nil {
		return err
	}
	
	process.RecordFailure()
	
	cmd := command.NotifyGroupCheckoutFailure{
		GroupCheckoutID: evt.GroupCheckoutID,
		FailedGuestIDs:  []string{evt.GuestStayID},
		CompletedCount: process.CompletedCount,
		FailedCount:    process.FailedCount,
	}
	
	return pm.commandBus.Send(ctx, cmd)
}

func (pm *GroupCheckoutProcessManager) getOrCreateProcess(
	groupCheckoutID string,
) (*GroupCheckoutProcess, error) {
	pm.mutex.RLock()
	process, exists := pm.processes[groupCheckoutID]
	pm.mutex.RUnlock()
	
	if !exists {
		return nil, fmt.Errorf("process not found: %s", groupCheckoutID)
	}
	
	return process, nil
}

// Cleanup old processes to prevent memory leaks
func (pm *GroupCheckoutProcessManager) CleanupOldProcesses(maxAge time.Duration) {
	pm.mutex.Lock()
	defer pm.mutex.Unlock()
	
	now := time.Now()
	for id, process := range pm.processes {
		if now.Sub(process.LastActivityAt) > maxAge {
			delete(pm.processes, id)
		}
	}
}
```

## 3. Event Store Integration

This example shows how to implement EventStoreDB integration for command and event storage.

### Event Store Implementation

```go
package store

import (
	"context"
	"encoding/json"
	"fmt"
	
	"github.com/EventStore/EventStore-Client-Go/esdb"
	"github.com/yourproject/internal/domain/event"
)

type EventStoreDB struct {
	client *esdb.Client
}

func NewEventStoreDB(client *esdb.Client) *EventStoreDB {
	return &EventStoreDB{
		client: client,
	}
}

func (es *EventStoreDB) SaveEvents(
	ctx context.Context,
	streamID string,
	expectedRevision esdb.ExpectedRevision,
	events []event.Event,
) error {
	var eventData []esdb.EventData
	
	for _, evt := range events {
		data, err := json.Marshal(evt)
		if err != nil {
			return fmt.Errorf("failed to marshal event: %w", err)
		}
		
		eventData = append(eventData, esdb.EventData{
			EventID:     uuid.New(),
			EventType:   evt.Type(),
			Data:        data,
			ContentType: "application/json",
		})
	}
	
	_, err := es.client.AppendToStream(
		ctx,
		streamID,
		esdb.AppendToStreamOptions{
			ExpectedRevision: expectedRevision,
		},
		eventData...,
	)
	
	return err
}

func (es *EventStoreDB) LoadEvents(
	ctx context.Context,
	streamID string,
	fromStream uint64,
) ([]event.Event, error) {
	readStream, err := es.client.ReadStream(
		ctx,
		streamID,
		esdb.ReadStreamOptions{
			From: esdb.Revision(fromStream),
		},
		100, // Max count
	)
	if err != nil {
		return nil, err
	}
	defer readStream.Close()
	
	var events []event.Event
	
	for {
		eventData, err := readStream.Recv()
		if err != nil {
			if err == esdb.ErrStreamNotFound {
				return nil, nil
			}
			return nil, err
		}
		
		if eventData.Event == nil {
			break // Stream ended
		}
		
		evt, err := es.deserializeEvent(eventData.Event)
		if err != nil {
			continue // Skip malformed events
		}
		
		events = append(events, evt)
	}
	
	return events, nil
}

func (es *EventStoreDB) deserializeEvent(esdbEvent *esdb.RecordedEvent) (event.Event, error) {
	// This would typically use a registry of event types
	switch esdbEvent.EventType {
	case "CartFinalized":
		var evt event.CartFinalized
		if err := json.Unmarshal(esdbEvent.Data, &evt); err != nil {
			return nil, err
		}
		return &evt, nil
		
	case "OrderInitialized":
		var evt event.OrderInitialized
		if err := json.Unmarshal(esdbEvent.Data, &evt); err != nil {
			return nil, err
		}
		return &evt, nil
		
	// ... other event types
	
	default:
		return nil, fmt.Errorf("unknown event type: %s", esdbEvent.EventType)
	}
}

// Subscribe to events
func (es *EventStoreDB) SubscribeToStream(
	ctx context.Context,
	streamID string,
	handler func(event.Event) error,
) error {
	subscription, err := es.client.SubscribeToStream(
		ctx,
		streamID,
		esdb.SubscribeToStreamOptions{
			From: esdb.Start{},
		},
	)
	if err != nil {
		return err
	}
	
	go func() {
		for {
			eventData, err := subscription.Recv()
			if err != nil {
				// Handle subscription error
				return
			}
			
			if eventData.Event != nil {
				evt, err := es.deserializeEvent(eventData.Event)
				if err != nil {
					continue // Skip malformed events
				}
				
				if err := handler(evt); err != nil {
					// Log error but continue processing
					continue
				}
			}
		}
	}()
	
	return nil
}
```

### Command Bus Implementation

```go
package command

import (
	"context"
	"encoding/json"
	
	"github.com/EventStore/EventStore-Client-Go/esdb"
	"github.com/yourproject/internal/domain/command"
)

type CommandEnvelope struct {
	Command   command.Command `json:"command"`
	Metadata CommandMetadata `json:"metadata"`
}

type CommandMetadata struct {
	CorrelationID string `json:"correlation_id"`
	CausationID   string `json:"causation_id"`
	Timestamp     string `json:"timestamp"`
}

type ESDBCommandBus struct {
	eventStore *store.EventStoreDB
	streamID   string
}

func NewESDBCommandBus(eventStore *store.EventStoreDB) *ESDBCommandBus {
	return &ESDBCommandBus{
		eventStore: eventStore,
		streamID:   "_commands-all",
	}
}

func (bus *ESDBCommandBus) Send(ctx context.Context, cmd command.Command) error {
	envelope := CommandEnvelope{
		Command: cmd,
		Metadata: CommandMetadata{
			CorrelationID: generateCorrelationID(ctx),
			CausationID:   generateCausationID(ctx),
			Timestamp:     time.Now().Format(time.RFC3339),
		},
	}
	
	return bus.eventStore.SaveCommand(ctx, bus.streamID, envelope)
}

// Command handler
type CommandHandler interface {
	Handle(ctx context.Context, cmd command.Command) error
}

type CommandProcessor struct {
	commandBus   *ESDBCommandBus
	handlers     map[string]CommandHandler
	retryPolicy  *RetryPolicy
}

func NewCommandProcessor(commandBus *ESDBCommandBus) *CommandProcessor {
	return &CommandProcessor{
		commandBus: commandBus,
		handlers:   make(map[string]CommandHandler),
		retryPolicy: NewDefaultRetryPolicy(),
	}
}

func (cp *CommandProcessor) Register(commandType string, handler CommandHandler) {
	cp.handlers[commandType] = handler
}

func (cp *CommandProcessor) Start(ctx context.Context) error {
	return cp.commandBus.Subscribe(ctx, func(envelope CommandEnvelope) error {
		cmdType := envelope.Command.Type()
		handler, exists := cp.handlers[cmdType]
		if !exists {
			return fmt.Errorf("no handler for command type: %s", cmdType)
		}
		
		// Use retry policy for handling transient errors
		return cp.retryPolicy.Run(func() error {
			return handler.Handle(ctx, envelope.Command)
		})
	})
}
```

## 4. Outbox Pattern Implementation

This example shows a complete outbox implementation for reliable event delivery.

### Outbox Store

```go
package outbox

import (
	"context"
	"database/sql"
	"time"
	
	"github.com/google/uuid"
)

type OutboxEntry struct {
	ID           string    `json:"id"`
	EventType    string    `json:"event_type"`
	EventData    []byte    `json:"event_data"`
	CreatedAt    time.Time `json:"created_at"`
	PublishedAt  *time.Time `json:"published_at"`
	PublishAttempts int     `json:"publish_attempts"`
}

type OutboxStore interface {
	Save(ctx context.Context, entries []OutboxEntry) error
	GetUnpublished(ctx context.Context, limit int) ([]OutboxEntry, error)
	MarkAsPublished(ctx context.Context, ids []string) error
	IncrementAttempts(ctx context.Context, id string) error
}

type SQLOutboxStore struct {
	db *sql.DB
}

func NewSQLOutboxStore(db *sql.DB) *SQLOutboxStore {
	return &SQLOutboxStore{db: db}
}

func (s *SQLOutboxStore) Save(ctx context.Context, entries []OutboxEntry) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	
	for _, entry := range entries {
		_, err := tx.ExecContext(ctx, `
			INSERT INTO outbox (id, event_type, event_data, created_at, publish_attempts)
			VALUES ($1, $2, $3, $4, $5)
		`, entry.ID, entry.EventType, entry.EventData, entry.CreatedAt, 0)
		if err != nil {
			return err
		}
	}
	
	return tx.Commit()
}

func (s *SQLOutboxStore) GetUnpublished(ctx context.Context, limit int) ([]OutboxEntry, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, event_type, event_data, created_at, published_at, publish_attempts
		FROM outbox
		WHERE published_at IS NULL 
		AND publish_attempts < 3
		ORDER BY created_at ASC
		LIMIT $1
	`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	
	var entries []OutboxEntry
	for rows.Next() {
		var entry OutboxEntry
		if err := rows.Scan(
			&entry.ID,
			&entry.EventType,
			&entry.EventData,
			&entry.CreatedAt,
			&entry.PublishedAt,
			&entry.PublishAttempts,
		); err != nil {
			return nil, err
		}
		entries = append(entries, entry)
	}
	
	return entries, nil
}

func (s *SQLOutboxStore) MarkAsPublished(ctx context.Context, ids []string) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	
	for _, id := range ids {
		_, err := tx.ExecContext(ctx, `
			UPDATE outbox 
			SET published_at = $1 
			WHERE id = $2
		`, time.Now(), id)
		if err != nil {
			return err
		}
	}
	
	return tx.Commit()
}

func (s *SQLOutboxStore) IncrementAttempts(ctx context.Context, id string) error {
	_, err := s.db.ExecContext(ctx, `
		UPDATE outbox 
		SET publish_attempts = publish_attempts + 1 
		WHERE id = $1
	`, id)
	return err
}
```

### Event Publisher

```go
package outbox

import (
	"context"
	"encoding/json"
	"time"
	
	"github.com/yourproject/internal/domain/event"
)

type EventPublisher struct {
	outbox     OutboxStore
	eventBus   event.Bus
	batchSize  int
	interval   time.Duration
}

func NewEventPublisher(outbox OutboxStore, eventBus event.Bus) *EventPublisher {
	return &EventPublisher{
		outbox:    outbox,
		eventBus:  eventBus,
		batchSize: 100,
		interval:  5 * time.Second,
	}
}

func (p *EventPublisher) SaveEvents(ctx context.Context, events []event.Event) error {
	var entries []OutboxEntry
	
	for _, evt := range events {
		data, err := json.Marshal(evt)
		if err != nil {
			return err
		}
		
		entries = append(entries, OutboxEntry{
			ID:        uuid.New().String(),
			EventType: evt.Type(),
			EventData: data,
			CreatedAt: time.Now(),
		})
	}
	
	return p.outbox.Save(ctx, entries)
}

func (p *EventPublisher) Start(ctx context.Context) {
	ticker := time.NewTicker(p.interval)
	defer ticker.Stop()
	
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			p.publishBatch(ctx)
		}
	}
}

func (p *EventPublisher) publishBatch(ctx context.Context) {
	entries, err := p.outbox.GetUnpublished(ctx, p.batchSize)
	if err != nil {
		return
	}
	
	if len(entries) == 0 {
		return
	}
	
	var publishedIDs []string
	
	for _, entry := range entries {
		evt, err := p.reconstructEvent(entry)
		if err != nil {
			p.outbox.IncrementAttempts(ctx, entry.ID)
			continue
		}
		
		if err := p.eventBus.Publish(ctx, evt); err != nil {
			p.outbox.IncrementAttempts(ctx, entry.ID)
			continue
		}
		
		publishedIDs = append(publishedIDs, entry.ID)
	}
	
	if len(publishedIDs) > 0 {
		p.outbox.MarkAsPublished(ctx, publishedIDs)
	}
}

func (p *EventPublisher) reconstructEvent(entry OutboxEntry) (event.Event, error) {
	// Implement event type registry and reconstruction logic
	return nil, nil
}
```