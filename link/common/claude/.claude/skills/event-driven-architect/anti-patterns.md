# Event-Driven Architecture Anti-Patterns

This document describes common anti-patterns in event-driven architecture with Go code examples showing the problems and their solutions.

## 1. Distributed Transaction Attempt

### Problem
Trying to maintain ACID transactions across multiple services using two-phase commit or similar mechanisms.

### Anti-Pattern Code

```go
// ANTI-PATTERN: Trying to coordinate distributed transactions
type DistributedTransactionManager struct {
	orderService    *OrderService
	paymentService  *PaymentService
	shipmentService *ShipmentService
}

func (dtm *DistributedTransactionManager) ProcessOrder(ctx context.Context, order Order) error {
	// This is a disaster - trying to coordinate multiple services atomically
	tx := dtm.beginDistributedTransaction()
	
	// Step 1: Create order
	if err := dtm.orderService.CreateOrder(ctx, order, tx); err != nil {
		tx.Rollback()
		return err
	}
	
	// Step 2: Process payment
	if err := dtm.paymentService.ProcessPayment(ctx, order.Payment, tx); err != nil {
		tx.Rollback()
		return err
	}
	
	// Step 3: Create shipment
	if err := dtm.shipmentService.CreateShipment(ctx, order.Shipment, tx); err != nil {
		tx.Rollback()
		return err
	}
	
	// What if shipment service is down? Everything hangs!
	return tx.Commit()
}
```

### Solution: Saga Pattern

```go
// SOLUTION: Use saga for distributed process
type OrderSaga struct {
	commandBus command.Bus
}

func (s *OrderSaga) HandleCartFinalized(ctx context.Context, evt event.CartFinalized) error {
	// Each step is independent with local transactions
	cmd := command.InitializeOrder{
		CartID:      evt.CartID,
		ClientID:    evt.ClientID,
		ProductItems: evt.ProductItems,
		TotalPrice:  evt.TotalPrice,
	}
	return s.commandBus.Send(ctx, cmd)
}

func (s *OrderSaga) HandleOrderInitialized(ctx context.Context, evt event.OrderInitialized) error {
	cmd := command.RequestPayment{
		OrderID:    evt.OrderID,
		TotalPrice: evt.TotalPrice,
	}
	return s.commandBus.Send(ctx, cmd)
}

func (s *OrderSaga) HandlePaymentCompleted(ctx context.Context, evt event.PaymentCompleted) error {
	cmd := command.SendPackage{
		OrderID:      evt.OrderID,
		ProductItems: evt.ProductItems,
	}
	return s.commandBus.Send(ctx, cmd)
}

// Compensation for failures
func (s *OrderSaga) HandlePaymentFailed(ctx context.Context, evt event.PaymentFailed) error {
	cmd := command.CancelOrder{
		OrderID: evt.OrderID,
		Reason:  OrderCancellationReasonPaymentFailed,
	}
	return s.commandBus.Send(ctx, cmd)
}
```

## 2. Leaking Internal Events

### Problem
Publishing domain events directly to external services, leaking internal implementation details.

### Anti-Pattern Code

```go
// ANTI-PATTERN: Publishing internal domain events directly
type OrderAggregate struct {
	id       string
	items    []OrderItem
	status   OrderStatus
	payment  *PaymentInfo
}

func (o *OrderAggregate) ConfirmPayment(paymentID string) error {
	// Internal event with sensitive implementation details
	evt := OrderPaymentConfirmedEvent{
		OrderID:     o.id,
		PaymentID:   paymentID,
		InternalStatus: o.status, // Internal enum
		PaymentMethod: o.payment.Method, // Internal payment details
		ValidationRules: o.getValidationRules(), // Internal logic
	}
	o.raiseEvent(evt)
	return nil
}

// This event is published directly to other services - BAD!
```

### Solution: Event Enrichment

```go
// SOLUTION: Transform internal events to external events
type OrderService struct {
	aggregateStore store.AggregateStore
	eventBus       event.Bus
}

func (s *OrderService) HandleOrderPaymentConfirmed(ctx context.Context, evt event.OrderPaymentConfirmed) error {
	// Load aggregate to enrich and transform
	order, err := s.aggregateStore.Load(ctx, evt.OrderID)
	if err != nil {
		return err
	}
	
	// Create clean external event
	externalEvent := event.OrderPaymentFinalized{
		OrderID:       evt.OrderID,
		ClientID:      order.ClientID(),
		PaymentAmount: order.TotalPrice(),
		FinalizedAt:   time.Now(),
		// No internal implementation details exposed
	}
	
	return s.eventBus.Publish(ctx, externalEvent)
}

// Internal event stays within the bounded context
type OrderAggregate struct {
	id       string
	items    []OrderItem
	status   OrderStatus
	payment  *PaymentInfo
}

func (o *OrderAggregate) ConfirmPayment(paymentID string) error {
	// Internal event - stays within this context
	evt := OrderPaymentConfirmedEvent{
		OrderID:   o.id,
		PaymentID: paymentID,
	}
	o.raiseEvent(evt)
	return nil
}
```

## 3. Missing Compensation

### Problem
Not defining rollback actions for failed operations, leaving system in inconsistent state.

### Anti-Pattern Code

```go
// ANTI-PATTERN: No compensation defined
type SimpleSaga struct {
	commandBus command.Bus
}

func (s *SimpleSaga) HandleOrderInitialized(ctx context.Context, evt event.OrderInitialized) error {
	// Charge payment - but what if it fails later?
	cmd := command.ChargePayment{
		OrderID:    evt.OrderID,
		Amount:     evt.TotalPrice,
		PaymentMethod: "credit_card",
	}
	return s.commandBus.Send(ctx, cmd)
}

func (s *SimpleSaga) HandlePaymentCharged(ctx context.Context, evt event.PaymentCharged) error {
	// Ship product - but what if shipping fails?
	cmd := command.ShipProduct{
		OrderID: evt.OrderID,
		Items:   evt.Items,
	}
	return s.commandBus.Send(ctx, cmd)
}

// Payment was charged but shipping failed - customer loses money!
```

### Solution: Full Compensation Flow

```go
// SOLUTION: Complete compensation flow
type OrderSaga struct {
	commandBus command.Bus
}

// Happy path
func (s *OrderSaga) HandleOrderInitialized(ctx context.Context, evt event.OrderInitialized) error {
	cmd := command.ChargePayment{
		OrderID:      evt.OrderID,
		Amount:       evt.TotalPrice,
		PaymentMethod: "credit_card",
	}
	return s.commandBus.Send(ctx, cmd)
}

func (s *OrderSaga) HandlePaymentCharged(ctx context.Context, evt event.PaymentCharged) error {
	cmd := command.ShipProduct{
		OrderID: evt.OrderID,
		Items:   evt.Items,
	}
	return s.commandBus.Send(ctx, cmd)
}

// Compensation flows
func (s *OrderSaga) HandlePaymentFailed(ctx context.Context, evt event.PaymentFailed) error {
	// Payment failed, cancel order
	cmd := command.CancelOrder{
		OrderID: evt.OrderID,
		Reason:  OrderCancellationReasonPaymentFailed,
	}
	return s.commandBus.Send(ctx, cmd)
}

func (s *OrderSaga) HandleShippingFailed(ctx context.Context, evt event.ShippingFailed) error {
	// Shipping failed, refund payment
	cmd := command.RefundPayment{
		PaymentID: evt.PaymentID,
		Amount:    evt.Amount,
		Reason:    ShippingFailedReason,
	}
	return s.commandBus.Send(ctx, cmd)
}

func (s *OrderSaga) HandleRefundProcessed(ctx context.Context, evt event.RefundProcessed) error {
	// Payment refunded, now cancel order
	cmd := command.CancelOrder{
		OrderID: evt.OrderID,
		Reason:  OrderCancellationReasonShippingFailed,
	}
	return s.commandBus.Send(ctx, cmd)
}
```

## 4. Synchronous Dependencies

### Problem
Services making direct synchronous calls to each other, creating tight coupling.

### Anti-Pattern Code

```go
// ANTI-PATTERN: Direct service calls creating tight coupling
type OrderService struct {
	paymentClient  *PaymentServiceClient
	shipmentClient *ShipmentServiceClient
}

func (s *OrderService) ProcessOrder(ctx context.Context, order Order) error {
	// Direct synchronous call - creates tight coupling
	paymentResult, err := s.paymentClient.ProcessPayment(ctx, PaymentRequest{
		OrderID: order.ID,
		Amount:  order.Total,
	})
	if err != nil {
		return err
	}
	
	// Another direct call - what if shipment service is down?
	shipmentResult, err := s.shipmentClient.CreateShipment(ctx, ShipmentRequest{
		OrderID: order.ID,
		Items:   order.Items,
	})
	if err != nil {
		// Now we need to manually rollback payment - complex!
		rollbackErr := s.paymentClient.RefundPayment(ctx, paymentResult.PaymentID)
		if rollbackErr != nil {
			// Now we have a bigger problem!
			return fmt.Errorf("shipment failed and rollback failed: %v, %v", err, rollbackErr)
		}
		return err
	}
	
	return nil
}
```

### Solution: Event-Driven Communication

```go
// SOLUTION: Event-driven communication
type OrderService struct {
	eventBus event.Bus
	store    store.OrderStore
}

func (s *OrderService) ProcessOrder(ctx context.Context, order Order) error {
	// Create order in our own database
	if err := s.store.Save(ctx, order); err != nil {
		return err
	}
	
	// Publish event - no direct dependencies
	evt := event.OrderCreated{
		OrderID:     order.ID,
		ClientID:    order.ClientID,
		TotalAmount: order.Total,
		CreatedAt:   time.Now(),
	}
	
	return s.eventBus.Publish(ctx, evt)
}

// Other services listen for events they care about
type PaymentService struct {
	commandBus command.Bus
}

func (s *PaymentService) HandleOrderCreated(ctx context.Context, evt event.OrderCreated) error {
	cmd := command.ProcessPayment{
		OrderID: evt.OrderID,
		Amount:  evt.TotalAmount,
	}
	return s.commandBus.Send(ctx, cmd)
}

type ShipmentService struct {
	commandBus command.Bus
}

func (s *ShipmentService) HandlePaymentCompleted(ctx context.Context, evt event.PaymentCompleted) error {
	cmd := command.CreateShipment{
		OrderID: evt.OrderID,
	}
	return s.commandBus.Send(ctx, cmd)
}
```

## 5. God Process Manager

### Problem
Single process manager handling all business logic, becoming a bottleneck and mixing concerns.

### Anti-Pattern Code

```go
// ANTI-PATTERN: God process manager doing everything
type OrderProcessManager struct {
	db         *sql.DB
	paymentDB  *sql.DB
	shipmentDB *sql.DB
	emailClient *EmailClient
	
	// State machine with too many states and transitions
	processes map[string]*OrderProcess
}

type OrderProcess struct {
	ID               string
	State           string // Many states: created, payment_pending, payment_processing, payment_completed, payment_failed, shipment_preparing, shipment_ready, shipment_dispatched, shipment_delivered, shipment_failed, completion_pending, completed, failed, cancellation_requested, cancellation_pending, cancelled...
	
	// Mixing all kinds of business logic
	Order           *Order
	Payment         *Payment
	Shipment        *Shipment
	EmailHistory    []Email
	CompensationLog []CompensationAction
	
	// Complex decision logic embedded here
}

func (pm *OrderProcessManager) HandleEvent(ctx context.Context, evt Event) error {
	process := pm.processes[evt.ProcessID]
	
	switch process.State {
	case "payment_pending":
		if evt.Type == "payment_requested" {
			// Payment logic mixed with shipment logic
			payment := &Payment{Amount: process.Order.Total}
			if err := pm.paymentDB.Save(payment); err != nil {
				return err
			}
			
			// Email logic in process manager
			if err := pm.emailClient.SendPaymentEmail(process.Order.ClientEmail); err != nil {
				return err
			}
			
			process.State = "payment_processing"
		}
		
	case "payment_completed":
		if evt.Type == "payment_confirmed" {
			// Shipment preparation logic here too
			shipment := &Shipment{OrderID: process.ID}
			if err := pm.shipmentDB.Save(shipment); err != nil {
				// Compensation logic mixed in
				pm.refundPayment(process.Payment)
				return err
			}
			
			// More email logic
			pm.emailClient.SendShipmentEmail(process.Order.ClientEmail)
			process.State = "shipment_preparing"
		}
		
	// ... many more cases handling all business logic
	}
	
	return nil
}
```

### Solution: Separate Concerns with Lightweight Saga

```go
// SOLUTION: Lightweight saga + separate services
type OrderSaga struct {
	commandBus command.Bus
}

// Saga only coordinates - doesn't contain business logic
func (s *OrderSaga) HandleOrderInitialized(ctx context.Context, evt event.OrderInitialized) error {
	cmd := command.ProcessPayment{
		OrderID:    evt.OrderID,
		Amount:     evt.TotalPrice,
		ClientEmail: evt.ClientEmail,
	}
	return s.commandBus.Send(ctx, cmd)
}

func (s *OrderSaga) HandlePaymentCompleted(ctx context.Context, evt event.PaymentCompleted) error {
	cmd := command.PrepareShipment{
		OrderID: evt.OrderID,
	}
	return s.commandBus.Send(ctx, cmd)
}

// Business logic stays in services
type PaymentService struct {
	paymentStore store.PaymentStore
	eventBus     event.Bus
	emailService *EmailService
}

func (s *PaymentService) HandleProcessPayment(ctx context.Context, cmd command.ProcessPayment) error {
	// Payment business logic
	payment := &Payment{
		OrderID: cmd.OrderID,
		Amount:  cmd.Amount,
		Status:  PaymentStatusPending,
	}
	
	if err := s.paymentStore.Save(ctx, payment); err != nil {
		return err
	}
	
	// Send notification - properly separated concern
	if err := s.emailService.SendPaymentConfirmation(ctx, cmd.ClientEmail); err != nil {
		// Log but don't fail the process
		s.logNotificationError(cmd.OrderID, err)
	}
	
	// Publish event
	evt := event.PaymentProcessed{
		OrderID:    cmd.OrderID,
		PaymentID:  payment.ID,
		Amount:     cmd.Amount,
		ProcessedAt: time.Now(),
	}
	
	return s.eventBus.Publish(ctx, evt)
}

type ShipmentService struct {
	shipmentStore store.ShipmentStore
	eventBus     event.Bus
}

func (s *ShipmentService) HandlePrepareShipment(ctx context.Context, cmd command.PrepareShipment) error {
	// Shipment business logic
	shipment := &Shipment{
		OrderID: cmd.OrderID,
		Status:  ShipmentStatusPreparing,
	}
	
	if err := s.shipmentStore.Save(ctx, shipment); err != nil {
		return err
	}
	
	// Publish event
	evt := event.ShipmentPrepared{
		OrderID:    cmd.OrderID,
		ShipmentID: shipment.ID,
		PreparedAt: time.Now(),
	}
	
	return s.eventBus.Publish(ctx, evt)
}
```

## 6. Unreliable Messaging

### Problem
Not ensuring message delivery guarantees, leading to lost events and inconsistent state.

### Anti-Pattern Code

```go
// ANTI-PATTERN: Publishing events without delivery guarantees
type OrderService struct {
	eventBus event.Bus
	db       *sql.DB
}

func (s *OrderService) CreateOrder(ctx context.Context, order Order) error {
	// Save order to database
	if err := s.db.Save(order); err != nil {
		return err
	}
	
	// Publish event - what if this fails?
	evt := event.OrderCreated{
		OrderID:   order.ID,
		ClientID:  order.ClientID,
		CreatedAt: time.Now(),
	}
	
	// If event publish fails, we have order in DB but no event!
	if err := s.eventBus.Publish(evt); err != nil {
		return err
	}
	
	return nil
}

// Or worse - fire and forget
func (s *OrderService) CreateOrderAsync(ctx context.Context, order Order) error {
	if err := s.db.Save(order); err != nil {
		return err
	}
	
	// Fire and forget - no error handling, no delivery guarantee
	go func() {
		evt := event.OrderCreated{OrderID: order.ID}
		s.eventBus.Publish(evt) // This could fail silently!
	}()
	
	return nil
}
```

### Solution: Outbox Pattern

```go
// SOLUTION: Outbox pattern for reliable delivery
type OrderService struct {
	db       *sql.DB
	outbox   OutboxStore
	publisher EventPublisher
}

func (s *OrderService) CreateOrder(ctx context.Context, order Order) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	
	// Save order in same transaction as events
	if err := s.saveOrderInTx(tx, order); err != nil {
		return err
	}
	
	// Create outbox entries in same transaction
	events := []event.Event{
		event.OrderCreated{
			OrderID:   order.ID,
			ClientID:  order.ClientID,
			CreatedAt: time.Now(),
		},
		event.OrderValidationRequested{
			OrderID: order.ID,
		},
	}
	
	if err := s.outbox.SaveInTx(tx, events); err != nil {
		return err
	}
	
	// Atomic commit of both order and events
	return tx.Commit()
}

// Separate process handles reliable publishing
type EventPublisher struct {
	outbox      OutboxStore
	eventBus    event.Bus
	batchSize   int
	pollInterval time.Duration
}

func (p *EventPublisher) Start(ctx context.Context) {
	ticker := time.NewTicker(p.pollInterval)
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
	// Get unpublished events
	entries, err := p.outbox.GetUnpublished(ctx, p.batchSize)
	if err != nil {
		return
	}
	
	var publishedIDs []string
	
	for _, entry := range entries {
		// Reconstruct event
		evt, err := p.reconstructEvent(entry)
		if err != nil {
			continue
		}
		
		// Try to publish
		if err := p.eventBus.Publish(ctx, evt); err != nil {
			continue // Skip for now, will retry later
		}
		
		publishedIDs = append(publishedIDs, entry.ID)
	}
	
	// Mark as published
	if len(publishedIDs) > 0 {
		p.outbox.MarkAsPublished(ctx, publishedIDs)
	}
}
```