# emod DSL

How to write the approved event model as an emod model. emod is an Event Modeling DSL in
HCL, with a CLI that checks a model and draws its diagrams:
<https://github.com/hpcsc/emod>. The full grammar is in `docs/dsl-reference.md` of that
repository.

The HCL grammar needs emod `v0.1.1` prereleases or later. An older build reports
`invalid version header: expected an integer after "emod", got "="` on line 1. In that
case, ask the user to run `emod update --prerelease`.

## Map the Model to emod

| Model element | Phase | emod construct |
|---|---|---|
| System or feature | 8 | `model`, one for each file |
| Actor who uses a screen | 1–3 | `actor` |
| Autonomous component | 6 | `context` |
| Aggregate (Aggregate pattern) | 7 | `aggregate`, in the `context` of its component |
| Rule that refuses a command | 4 | an `invariants` entry on the aggregate, a `command -> rejected:` line in the `flow`, and a `rejected(...)` spec |
| Implementation slice | 8 | `slice`, one for each use case: a command with its events, a view, or an automation with its command. When a row of the Implementation Slices table holds more than one use case, write one `slice` for each, and use the names of that table |
| Screen action (UI Trigger) | 3, 7 | `trigger` with `actor`, and `reads` for the view that backs the screen |
| Command and the events it produces | 4 | `command`, `event`, and a `command -> event:` line in the `flow` of one slice |
| View (Projection) | 4, 7 | `view` with `subscribes`, in a slice of its own |
| Reactor, Policy, Process Manager | 7 | `automation` with `on`, `reads` (its todo list) and `command`. Add `after = "24h"` for a delay |
| Scheduler | 7 | `automation` with `every = "0 2 * * *"` (cron) or `every = "5m"` in place of `on` |
| Translation (inbound) | 7 | `translation` with `external_system`, `reads`, `command` and a nested `event` |
| Event that an external system records, with no translation | 4 | `event` with `source = external("<system>")` |
| Gateway (outbound) | 7 | the `automation` that issues the command. The command appends no event, so its spec states `then = []`. The confirmation from the provider comes back as a `translation`. Do not add a `...Sent` event |
| Command field, with its source | 4 | `fields` entry: `name = required(type)` or `name = optional(type)` |
| View field, with its lineage | 4 | `fields` entry on the `view` |

emod has no construct for capabilities, processes, storyboards, field sources, view data
lineage, or the labels of the message processing patterns. These stay in the Markdown
document.

## Place the Slices

1. Write one `context` for each autonomous component, in the order of Phase 6.
2. Write one `aggregate` for each aggregate of Phase 7, in the context of the component
   that owns its commands. If Phase 7 names no aggregate for a component, ask the user
   which consistency boundary owns its commands.
3. Put each command slice in the aggregate that owns the command. Write the slices of each
   aggregate in timeline order.
4. Put each automation in the slice of the command that it issues. Then the automation
   needs no `target`. Write `target { context = <Name> }` only when the automation is in a
   different context from its command.
5. Put each view slice in the aggregate that declares most of the events the view
   subscribes to. `subscribes` and `reads` resolve across the whole model.
6. Run `emod slices arrange` to put the view slices in their place. It moves only view
   slices, and it keeps the order of the other slices.

## Write the Specs

Write one spec for each outcome that the approved model states:

| Slice | Spec |
|---|---|
| Command slice | `when = <Command>`, `then = [<Event>]` for each event in its `flow` |
| Command slice, for each `command -> rejected:` line | `given` the events that make the rule apply, `when = <Command>`, `then = rejected(<Invariant>)` |
| View slice | `given = [<Event>, ...]`, `then = view(<View>)`, no `when` |
| Automation on an event | `when = <Event>`, `then = command(<Command>)` |
| Automation on a schedule | `given = [<Event>, ...]`, `then = command(<Command>)`, no `when` |
| Translation | the same as a command slice |

A spec name is a sentence about the outcome, for example `"refuses an order with no
lines"`. Example payloads are optional. Write them only with values from the storyboards
or from the user: `when = PlaceOrder({ lineCount = 0 })`.

## Rules the Checks Enforce

`emod validate` and `emod lint` both exit 1 on any finding, also on a warning or an info
finding. These are the findings an event model meets most often:

- **`given` stays in its aggregate.** A spec's `given` names only events that the slices of
  its own aggregate declare. This applies to view specs too
  (`spec/given-outside-boundary`).
- **Each command has a spec.** When the model has one spec, each command needs a spec whose
  `when` names it (`spec/command-without-spec`).
- **Each command with a spec has a rejection spec** (`spec/no-rejection-path`).
- **Each rule has a rejection spec.** Each invariant needs a `rejected(...)` spec in its own
  scope (`spec/invariant-never-exercised`). Each `command -> rejected:` line needs one in
  the same slice (`flow/rejection-without-spec`).
- **Each view has a reader.** A `trigger`, an `automation` or a `translation` names it in
  `reads` (`view/never-read`).
- **Each automation has a todo list** in `reads` (`automation/missing-todo-list`).
- **Each command has a pathway and each event has a producer.** A `flow`, an `automation`
  or a `translation` names each command. A `flow`, a `translation` or
  `source = external(...)` produces each event (`orphan-command`, `orphan-event`).
- **Names.** A command is in the imperative and does not end in `ed`. A view ends in
  `View`. An event does not end in `Updated`, `Changed`, `Modified` or `Initiated`. An event
  carries more than one ID field (`clickbait-event`).
- **Size.** A view subscribes to at most four events (`god-view`). At most two flows,
  automations or translations issue one command (`left-chair`).

A finding that only a new rule, element or name can fix goes back to the user. Do not
invent a business rule to make lint pass. Run `emod lint --explain <rule>` for the full
description of a rule.

## Syntax

- The first line is `emod = 1`.
- A block label is quoted: `command "PlaceOrder" { ... }`. A reference is not quoted:
  `reads = OrderSummaryView`, `subscribes = [OrderPlaced, OrderCancelled]`.
- `flow` is a heredoc, because HCL has no arrow operator.
- The field types that specs check are `string`, `date`, `timestamp`, `uuid`, `int`,
  `decimal` and `bool`. Any other name is a domain type.
- A comment starts with `#`. `emod fmt` keeps a comment above the construct it was above.

## Example

This model passes `emod validate`, `emod lint`, `emod fmt --check` and
`emod slices arrange --check`. It shows the command, view, automation and translation
patterns, rules, and the four kinds of spec.

```hcl
emod = 1

model "Order Fulfillment" {
  description = "How the shop takes an order and gets it paid"
}

actor "Customer" {
  description = "A person who buys from the shop"
}

context "OrderBooking" {
  description = "Takes orders and cancels them"

  aggregate "Order" {
    description = "One order, from placement to cancellation"

    invariants {
      OrderHasLines = "An order holds at least one line"
      CancelledOnce = "An order is cancelled at most once"
    }

    slice "Place Order" {
      description = "A customer orders the items in the cart"

      trigger "Checkout Screen" {
        description = "The form where the customer enters the address and pays"
        actor       = Customer
      }

      command "PlaceOrder" {
        description = "Ask the shop to take an order for the cart"

        fields {
          orderId         = required(uuid)
          customerId      = required(string)
          shippingAddress = required(string)
          lineCount       = required(int)
          total           = required(decimal)
        }
      }

      event "OrderPlaced" {
        description = "The shop took an order"

        fields {
          orderId         = required(uuid)
          customerId      = required(string)
          shippingAddress = required(string)
          total           = required(decimal)
          placedAt        = required(timestamp)
        }
      }

      flow = <<-FLOW
        command -> event:    PlaceOrder -> OrderPlaced
        command -> rejected: PlaceOrder -> OrderHasLines
      FLOW

      spec "takes an order for the items in the cart" {
        when = PlaceOrder
        then = [OrderPlaced]
      }

      spec "refuses an order with no lines" {
        when = PlaceOrder({ lineCount = 0 })
        then = rejected(OrderHasLines)
      }
    }

    slice "View Order Summary" {
      description = "What the customer sees about an order"

      view "OrderSummaryView" {
        description = "One order with its payment status"
        subscribes  = [OrderPlaced, PaymentSucceeded, PaymentFailed, OrderCancelled]

        fields {
          orderNumber   = required(uuid)
          total         = required(decimal)
          paymentStatus = required(string)
        }
      }

      spec "shows a cancelled order" {
        given = [OrderPlaced, OrderCancelled]
        then  = view(OrderSummaryView)
      }
    }

    slice "Cancel Order" {
      description = "A customer cancels an order"

      trigger "Order Confirmation Screen" {
        actor = Customer
        reads = OrderSummaryView
      }

      command "CancelOrder" {
        fields {
          orderId = required(uuid)
          reason  = required(string)
        }
      }

      event "OrderCancelled" {
        fields {
          orderId     = required(uuid)
          reason      = required(string)
          cancelledAt = required(timestamp)
        }
      }

      flow = <<-FLOW
        command -> event:    CancelOrder -> OrderCancelled
        command -> rejected: CancelOrder -> CancelledOnce
      FLOW

      spec "cancels an open order" {
        given = [OrderPlaced]
        when  = CancelOrder
        then  = [OrderCancelled]
      }

      spec "refuses to cancel an order twice" {
        given = [OrderPlaced, OrderCancelled]
        when  = CancelOrder
        then  = rejected(CancelledOnce)
      }
    }
  }
}

context "Payment" {
  description = "Charges the customer for an order"

  aggregate "Payment" {
    description = "The charges for one order"

    invariants {
      PaidOnce               = "An order is paid at most once"
      RefundWithinPaidAmount = "The refunds of a payment add up to at most the amount paid"
    }

    slice "Process Payment" {
      description = "The shop charges the customer for a new order"

      command "ProcessPayment" {
        fields {
          orderId = required(uuid)
          amount  = required(decimal)
        }
      }

      event "PaymentSucceeded" {
        fields {
          paymentId = required(string)
          orderId   = required(uuid)
          amount    = required(decimal)
          paidAt    = required(timestamp)
        }
      }

      event "PaymentFailed" {
        fields {
          orderId  = required(uuid)
          reason   = required(string)
          failedAt = required(timestamp)
        }
      }

      automation "PaymentReactor" {
        on      = OrderPlaced
        reads   = PendingPaymentsView
        command = ProcessPayment
      }

      flow = <<-FLOW
        command -> event:    ProcessPayment -> PaymentSucceeded
        command -> event:    ProcessPayment -> PaymentFailed
        command -> rejected: ProcessPayment -> PaidOnce
      FLOW

      spec "asks for a payment when an order is placed" {
        when = OrderPlaced
        then = command(ProcessPayment)
      }

      spec "charges the customer" {
        when = ProcessPayment({ amount = 42.50 })
        then = [PaymentSucceeded({ amount = 42.50 })]
      }

      spec "records a declined card" {
        when = ProcessPayment
        then = [PaymentFailed({ reason = "card declined" })]
      }

      spec "refuses to charge a paid order" {
        given = [PaymentSucceeded]
        when  = ProcessPayment
        then  = rejected(PaidOnce)
      }
    }

    slice "View Pending Payments" {
      description = "The orders the payment reactor has left to charge"

      view "PendingPaymentsView" {
        subscribes = [OrderPlaced, PaymentSucceeded, PaymentFailed]

        fields {
          orderId  = required(uuid)
          amount   = required(decimal)
          placedAt = required(timestamp)
        }
      }

      spec "drops an order once it is paid" {
        given = [PaymentSucceeded]
        then  = view(PendingPaymentsView)
      }
    }

    slice "View Paid Orders" {
      description = "The payments a refund from Stripe can match"

      view "PaidOrdersView" {
        subscribes = [PaymentSucceeded, RefundRecorded]

        fields {
          paymentId = required(string)
          orderId   = required(uuid)
          amount    = required(decimal)
        }
      }

      spec "lists the paid orders" {
        given = [PaymentSucceeded]
        then  = view(PaidOrdersView)
      }
    }

    slice "Record Refund" {
      description = "Stripe reports a refund that support made in the Stripe dashboard"

      command "RecordRefund" {
        fields {
          paymentId = required(string)
          amount    = required(decimal)
        }
      }

      translation "StripeRefundTranslator" {
        external_system = "Stripe"
        reads           = PaidOrdersView
        command         = RecordRefund

        event "RefundRecorded" {
          fields {
            paymentId  = required(string)
            orderId    = required(uuid)
            amount     = required(decimal)
            refundedAt = required(timestamp)
          }
        }
      }

      flow = <<-FLOW
        command -> rejected: RecordRefund -> RefundWithinPaidAmount
      FLOW

      spec "records a refund that Stripe reports" {
        given = [PaymentSucceeded]
        when  = RecordRefund
        then  = [RefundRecorded]
      }

      spec "refuses a refund larger than the payment" {
        given = [PaymentSucceeded({ amount = 42.50 })]
        when  = RecordRefund({ amount = 50 })
        then  = rejected(RefundWithinPaidAmount)
      }
    }
  }
}
```

An outbound gateway adds an automation whose command appends no event. Its rejection
spec uses the rule that stops a second send:

```hcl
    slice "Send Receipt" {
      command "SendReceipt" {
        fields {
          paymentId = required(string)
          email     = required(string)
        }
      }

      automation "ReceiptReactor" {
        on      = PaymentSucceeded
        reads   = ReceiptsToSendView
        command = SendReceipt
      }

      flow = <<-FLOW
        command -> rejected: SendReceipt -> OneReceiptPerPayment
      FLOW

      spec "asks for a receipt when a payment succeeds" {
        when = PaymentSucceeded
        then = command(SendReceipt)
      }

      spec "calls SendGrid and appends nothing" {
        when = SendReceipt
        then = []
      }

      spec "refuses to send a receipt that SendGrid delivered" {
        given = [ReceiptDelivered]
        when  = SendReceipt
        then  = rejected(OneReceiptPerPayment)
      }
    }
```

## Check the Model

Run these commands from the repository root, in this order:

```bash
emod slices arrange docs/event-model-[feature-name].emod
emod fmt docs/event-model-[feature-name].emod
emod validate docs/event-model-[feature-name].emod
emod lint docs/event-model-[feature-name].emod
emod diagram docs/event-model-[feature-name].emod --format drawio --specs \
  -o docs/event-model-[feature-name].drawio
```

`validate` and `lint` must exit 0. `emod slices arrange` reports the references that
still point backward. Some of them stay in every order, so they are not a finding.
