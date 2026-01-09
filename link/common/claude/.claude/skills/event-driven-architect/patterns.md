# Event-Driven Architecture Patterns

This document provides detailed descriptions of event-driven architecture patterns with Go code examples following the platform's conventions.

## 1. Saga Pattern

### Description
A saga is a stateless coordinator that reacts to events and dispatches commands based on those events. It's lightweight and doesn't maintain state between operations.

### When to Use
- Simple to moderate complexity workflows
- When most decisions can be made based on event data alone
- When you want minimal coordination overhead
- Most common distributed process scenarios

### Go Implementation

#### Basic Saga Structure

```go
package saga

import (
	"context"
	
	"github.com/yourproject/internal/domain/command"
	"github.com/yourproject/internal/domain/event"
)

// OrderSaga handles order processing workflow
type OrderSaga struct {
	commandBus command.Bus
}

// NewOrderSaga creates a new order saga
func NewOrderSaga(commandBus command.Bus) *OrderSaga {
	return &OrderSaga{
		commandBus: commandBus,
	}
}

// Handle CartFinalized event
func (s *OrderSaga) HandleCartFinalized(ctx context.Context, evt event.CartFinalized) error {
	cmd := command.InitializeOrder{
		CartID:      evt.CartID,
		ClientID:    evt.ClientID,
		ProductItems: evt.ProductItems,
		TotalPrice:  evt.TotalPrice,
	}
	
	return s.commandBus.Send(ctx, cmd)
}

// Handle OrderInitialized event
func (s *OrderSaga) HandleOrderInitialized(ctx context.Context, evt event.OrderInitialized) error {
	cmd := command.RequestPayment{
		OrderID:    evt.OrderID,
		TotalPrice: evt.TotalPrice,
	}
	
	return s.commandBus.Send(ctx, cmd)
}

// Handle PaymentCompleted event
func (s *OrderSaga) HandlePaymentCompleted(ctx context.Context, evt event.PaymentCompleted) error {
	cmd := command.SendPackage{
		OrderID:      evt.OrderID,
		ProductItems: evt.ProductItems,
	}
	
	return s.commandBus.Send(ctx, cmd)
}

// Handle PaymentFailed event - compensation flow
func (s *OrderSaga) HandlePaymentFailed(ctx context.Context, evt event.PaymentFailed) error {
	cmd := command.CancelOrder{
		OrderID: evt.OrderID,
		Reason:  OrderCancellationReasonPaymentFailed,
	}
	
	return s.commandBus.Send(ctx, cmd)
}
```

#### Saga Event Handler Registration

```go
package handlers

import (
	"github.com/yourproject/internal/domain/event"
	"github.com/yourproject/internal/usecase/provisioning/saga"
)

// SagaEventHandler registers saga handlers
type SagaEventHandler struct {
	orderSaga *saga.OrderSaga
}

func NewSagaEventHandler(orderSaga *saga.OrderSaga) *SagaEventHandler {
	return &SagaEventHandler{
		orderSaga: orderSaga,
	}
}

func (h *SagaEventHandler) RegisterHandlers(eventHandler event.Handler) {
	eventHandler.Register(event.CartFinalized{}, h.orderSaga.HandleCartFinalized)
	eventHandler.Register(event.OrderInitialized{}, h.orderSaga.HandleOrderInitialized)
	eventHandler.Register(event.PaymentCompleted{}, h.orderSaga.HandlePaymentCompleted)
	eventHandler.Register(event.PaymentFailed{}, h.orderSaga.HandlePaymentFailed)
}
```

## 2. Process Manager Pattern

### Description
A process manager maintains state and makes decisions based on both incoming events and current process state. It's modeled as a state machine.

### When to Use
- Complex workflows with many decision points
- When you need to wait for multiple events before proceeding
- When process flow depends on accumulated state
- Complex business processes with many conditional paths

### Go Implementation

#### Process Manager with State

```go
package processmanager

import (
	"context"
	"sync"
	"time"
	
	"github.com/yourproject/internal/domain/command"
	"github.com/yourproject/internal/domain/event"
)

// ProcessState represents the state of a distributed process
type ProcessState int

const (
	StateStarted ProcessState = iota
	StatePaymentInitiated
	StatePaymentCompleted
	StateShipmentInitiated
	StateCompleted
	StateFailed
)

// GroupCheckoutProcessManager handles complex group checkout workflow
type GroupCheckoutProcessManager struct {
	commandBus command.Bus
	states     map[string]*ProcessInstance
	mutex      sync.RWMutex
}

type ProcessInstance struct {
	ID               string
	GuestStayIDs     []string
	State            ProcessState
	CompletedCount   int
	FailedCount      int
	StartedAt        time.Time
	LastActivityAt   time.Time
}

func NewGroupCheckoutProcessManager(commandBus command.Bus) *GroupCheckoutProcessManager {
	return &GroupCheckoutProcessManager{
		commandBus: commandBus,
		states:     make(map[string]*ProcessInstance),
	}
}

func (pm *GroupCheckoutProcessManager) HandleGroupCheckoutInitiated(
	ctx context.Context, 
	evt event.GroupCheckoutInitiated,
) error {
	pm.mutex.Lock()
	defer pm.mutex.Unlock()
	
	instance := &ProcessInstance{
		ID:           evt.GroupCheckoutID,
		GuestStayIDs: evt.GuestStayIDs,
		State:        StateStarted,
		StartedAt:    time.Now(),
		LastActivityAt: time.Now(),
	}
	
	pm.states[evt.GroupCheckoutID] = instance
	
	// Initiate checkout for all guests
	for _, guestID := range evt.GuestStayIDs {
		cmd := command.CheckoutGuestAccount{
			GuestStayID:      guestID,
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
	pm.mutex.Lock()
	defer pm.mutex.Unlock()
	
	instance, exists := pm.states[evt.GroupCheckoutID]
	if !exists {
		return nil // Ignore unknown process
	}
	
	instance.CompletedCount++
	instance.LastActivityAt = time.Now()
	
	// Check if all guests have completed checkout
	if instance.CompletedCount+len(instance.FailedCount) >= len(instance.GuestStayIDs) {
		if instance.FailedCount == 0 {
			instance.State = StateCompleted
			// Send completion command
			cmd := command.CompleteGroupCheckout{
				GroupCheckoutID: evt.GroupCheckoutID,
			}
			return pm.commandBus.Send(ctx, cmd)
		}
	}
	
	return nil
}

func (pm *GroupCheckoutProcessManager) HandleGuestCheckoutFailed(
	ctx context.Context,
	evt event.GuestCheckoutFailed,
) error {
	pm.mutex.Lock()
	defer pm.mutex.Unlock()
	
	instance, exists := pm.states[evt.GroupCheckoutID]
	if !exists {
		return nil // Ignore unknown process
	}
	
	instance.FailedCount++
	instance.LastActivityAt = time.Now()
	
	// If any checkout fails, mark process as failed
	instance.State = StateFailed
	
	// Send failure notification
	cmd := command.NotifyGroupCheckoutFailure{
		GroupCheckoutID: evt.GroupCheckoutID,
		FailedGuestIDs:   []string{evt.GuestStayID},
	}
	
	return pm.commandBus.Send(ctx, cmd)
}
```

## 3. Choreography Pattern

### Description
Choreography is decentralized coordination where services react to each other's events without a central coordinator. Each service knows when to react to certain events.

### When to Use
- When you want to avoid single point of failure
- When services can operate independently
- When the workflow is relatively simple
- When you want maximum decoupling between services

### Go Implementation

#### Service Reacting to Events

```go
package shipment

import (
	"context"
	
	"github.com/yourproject/internal/domain/command"
	"github.com/yourproject/internal/domain/event"
)

// ShipmentService handles shipping operations through choreography
type ShipmentService struct {
	commandBus command.Bus
	// Other dependencies...
}

func NewShipmentService(commandBus command.Bus) *ShipmentService {
	return &ShipmentService{
		commandBus: commandBus,
	}
}

// React to payment completion - no central coordinator needed
func (s *ShipmentService) HandlePaymentCompleted(ctx context.Context, evt event.PaymentCompleted) error {
	// Check if product is available
	if s.isProductAvailable(evt.ProductItems) {
		cmd := command.SendPackage{
			OrderID:      evt.OrderID,
			ProductItems: evt.ProductItems,
		}
		return s.commandBus.Send(ctx, cmd)
	}
	
	// If product not available, emit event for other services to handle
	cmd := command.NotifyOutOfStock{
		OrderID:      evt.OrderID,
		ProductItems: evt.ProductItems,
	}
	return s.commandBus.Send(ctx, cmd)
}

func (s *ShipmentService) isProductAvailable(items []ProductItem) bool {
	// Business logic to check product availability
	for _, item := range items {
		if !s.checkInventory(item.ProductID, item.Quantity) {
			return false
		}
	}
	return true
}
```

#### Event Registration for Choreography

```go
package main

import (
	"github.com/yourproject/internal/shipment"
	"github.com/yourproject/internal/payment"
	"github.com/yourproject/internal/domain/event"
)

func setupChoreography(eventBus event.Bus) {
	shipmentService := shipment.NewShipmentService(commandBus)
	paymentService := payment.NewPaymentService(commandBus)
	
	// Each service registers for events it cares about
	eventBus.Subscribe(event.PaymentCompleted{}, shipmentService.HandlePaymentCompleted)
	eventBus.Subscribe(event.OrderCancelled{}, paymentService.HandleOrderCancelled)
	eventBus.Subscribe(event.PackageSent{}, paymentService.HandlePackageSent)
}
```

## 4. Event Enrichment Pattern

### Description
Transform internal domain events into external events that are appropriate for other services to consume, often adding context or hiding internal details.

### Go Implementation

```go
package external

import (
	"context"
	
	"github.com/yourproject/internal/domain/event"
	"github.com/yourproject/internal/domain/aggregate"
	"github.com/yourproject/internal/store"
)

// ShoppingCartExternalEventForwarder enriches and forwards internal events
type ShoppingCartExternalEventForwarder struct {
	aggregateStore store.AggregateStore
	eventBus       event.Bus
}

func NewShoppingCartExternalEventForwarder(
	aggregateStore store.AggregateStore,
	eventBus event.Bus,
) *ShoppingCartExternalEventForwarder {
	return &ShoppingCartExternalEventForwarder{
		aggregateStore: aggregateStore,
		eventBus:       eventBus,
	}
}

func (f *ShoppingCartExternalEventForwarder) HandleCartConfirmed(
	ctx context.Context,
	evt event.CartConfirmed,
) error {
	// Load the aggregate to enrich the event
	cart, err := f.aggregateStore.Load(ctx, evt.CartID)
	if err != nil {
		return err
	}
	
	// Create external event with enriched data
	externalEvent := event.ShoppingCartFinalized{
		CartID:       evt.CartID,
		ClientID:     cart.ClientID(),
		ProductItems: cart.ProductItems(),
		TotalPrice:   cart.TotalPrice(),
		ConfirmedAt:  evt.ConfirmedAt,
	}
	
	return f.eventBus.Publish(ctx, externalEvent)
}
```

## 5. Outbox Pattern

### Description
Ensures reliable event delivery by storing events and state changes in the same atomic transaction, then separately publishing events.

### Go Implementation

```go
package outbox

import (
	"context"
	"encoding/json"
	"time"
	
	"github.com/yourproject/internal/domain/event"
)

// OutboxEntry represents an event to be published
type OutboxEntry struct {
	ID        string    `json:"id"`
	EventID   string    `json:"event_id"`
	EventType string    `json:"event_type"`
	EventData []byte    `json:"event_data"`
	CreatedAt time.Time `json:"created_at"`
	Published bool      `json:"published"`
}

// OutboxStore handles outbox persistence
type OutboxStore interface {
	Save(ctx context.Context, entries []OutboxEntry) error
	GetUnpublished(ctx context.Context, limit int) ([]OutboxEntry, error)
	MarkAsPublished(ctx context.Context, ids []string) error
}

// OutboxPublisher handles publishing outbox events
type OutboxPublisher struct {
	store     OutboxStore
	eventBus  event.Bus
	batchSize int
}

func NewOutboxPublisher(store OutboxStore, eventBus event.Bus) *OutboxPublisher {
	return &OutboxPublisher{
		store:     store,
		eventBus:  eventBus,
		batchSize: 100,
	}
}

// SaveEvents saves events to outbox in the same transaction as business logic
func (p *OutboxPublisher) SaveEvents(ctx context.Context, events []event.Event) error {
	var entries []OutboxEntry
	
	for _, evt := range events {
		data, err := json.Marshal(evt)
		if err != nil {
			return err
		}
		
		entries = append(entries, OutboxEntry{
			ID:        generateID(),
			EventID:   evt.ID(),
			EventType: evt.Type(),
			EventData: data,
			CreatedAt: time.Now(),
			Published: false,
		})
	}
	
	return p.store.Save(ctx, entries)
}

// PublishUnpublished processes and publishes events from outbox
func (p *OutboxPublisher) PublishUnpublished(ctx context.Context) error {
	entries, err := p.store.GetUnpublished(ctx, p.batchSize)
	if err != nil {
		return err
	}
	
	if len(entries) == 0 {
		return nil
	}
	
	var publishedIDs []string
	
	for _, entry := range entries {
		// Reconstruct event from stored data
		evt, err := p.reconstructEvent(entry)
		if err != nil {
			continue // Skip malformed events
		}
		
		if err := p.eventBus.Publish(ctx, evt); err != nil {
			continue // Continue with other events if one fails
		}
		
		publishedIDs = append(publishedIDs, entry.ID)
	}
	
	// Mark successfully published events
	return p.store.MarkAsPublished(ctx, publishedIDs)
}

func (p *OutboxPublisher) reconstructEvent(entry OutboxEntry) (event.Event, error) {
	// Logic to reconstruct event type and data
	// This would typically involve a registry of event types
	return nil, nil
}
```