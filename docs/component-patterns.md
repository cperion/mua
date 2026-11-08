# Component patterns in Mua

**A component's behavioral surface can be a stateful vocabulary: ordinary functions and
values grouped with `define`, with private state captured by closures.** Its parent connects
that vocabulary to those of its children. No component class, inheritance hierarchy, event
bus or new syntax is required.

This records the patterns agreed while discussing a Mua UI framework over BUI. It does **not**
specify a BUI binding, widget API, rendering model, scheduler or mounting implementation.
The examples are headless behavioral components, not implemented UI widgets.

[Designing and writing Mua](designing-and-writing-mua.md) owns the activity and vocabulary
principles; [the compiler guide](writing-compilers.md#45-designing-the-state-an-operation-carries)
explains state ownership, captures and boundaries; [the syntax guide](syntax.md) owns application,
`define`, `with` and opening. The `lua` blocks here form one program, checked for formatting,
translated and run by `tests/guide.lua`.

## 1. Separate the directions

A function's role matters more than the fact that it is a callback:

| Role | Direction of use | Meaning | Examples |
|---|---|---|---|
| inputs | parent supplies values to child | what the component is given | initial value, document, enabled |
| capabilities | parent calls into child | what others may ask it to do or read | `insert`, `undo`, `focus`, `current` |
| events / continuations | child calls outward | what it reports or requests | `changed`, `submit_requested` |
| completion | activity reports to caller | how bounded work ended | `accepted`, `cancelled`, `failed` |

**The vocabulary travels opposite to the calls it enables.** The parent supplies an outward
notification vocabulary; the child calls it. The child supplies its capabilities; the parent
calls them. Do not mix these two roles into one undifferentiated context.

Commands ask; events tell; outcomes finish. `save` asks for work, `save_requested` reports an
intention, and `saved` reports success. A button activation is not evidence that saving succeeded.
Queries such as `current` read state without requesting a change.

An event can carry a request rather than a fact. State whether its handler must return a
response or is only being notified; do not silently switch between the two protocols.

## 2. A component instance is a vocabulary, not a new object system

`define` groups names. It does not allocate private state, establish a lifetime, or give a table
nominal identity. A factory creates independent state and the functions that reach it.
A component that needs no state need not manufacture any.

Here a counter accepts initial data, then an outward notification vocabulary, and returns its
inward capabilities. It snapshots the initial number and the chosen notification function at
construction; these are not reactive bindings to the supplied tables.

```lua
local counter = do(inputs)
    if type inputs ~= "table" or not check(Number, inputs.initial) then
        error("counter: inputs.initial expects Number", 2)
    end
    local initial = inputs.initial
    return do(Notify)
        if type Notify ~= "table" or type Notify.changed ~= "function" then
            error("counter: Notify.changed expects a function", 2)
        end
        local value = initial
        local changed = Notify.changed
        return define
            increment = do()
                value += 1
                changed value
            end
            current = || -> value
        end
    end
end

local observations = {}
local counting = counter define
    initial = 0
end define
    changed = do(value)
        observations[#observations + 1] = value
    end
end
counting.increment
assert(counting.current() == 1 and observations[1] == 1)
assert(not pcall(counter, { initial = "zero" }))
assert(not pcall(counter { initial = 0 }, {}))
```

The construction contract checks required data and behavior at the boundary. The vocabulary
stays structural; it needs no nominal interface type merely to group two operations. Introduce
a `struct` or `oneof` only for the triggers in the design guide, not for every component.

The counter changes its state **before** notifying, synchronously. The handler's return value
has no meaning in this notification protocol. If the handler raises an error, the increment has
already happened: this component promises no rollback. Reentrancy and asynchronous delivery are
not supplied by `define`; a component or its owner must choose those policies explicitly.

```lua
local failing_counting = counter define
    initial = 8
end define
    changed = do()
        error("notification failed", 0)
    end
end
local notified, problem = pcall failing_counting.increment
assert(not notified and problem == "notification failed")
assert(failing_counting.current() == 9)
```

## 3. Chained `define` blocks are ordinary application

The construction above is `counter(inputs)(Notify)`: the first call returns the function that
accepts the second vocabulary. Application provides the chain; `define` itself just produces a
table. The signature gives each stage its role:

```text
initial data → supplied outward notifications → returned inward capabilities
```

The result `counting` is a table, not another curried stage. Appending another `define` block
would try to call that table. A further composition stage must be an actual function in the
chosen API, not an assumed property of `define`.

`with` can also supply a keyed argument. This is the same counter factory, not a second
construction mechanism:

```lua
local other_observations = {}
local other_inputs = with
    initial = 10
end
local other_counting = counter other_inputs define
    changed = do(value)
        other_observations[#other_observations + 1] = value
    end
end
other_counting.increment
assert(other_counting.current() == 11 and other_observations[1] == 11)
assert(counting.current() == 1 and #observations == 1)
```

Use `define` for a vocabulary. Use `with` for supplied data, particularly where a declared type
will recognize it. Without such a type, both examples pass ordinary tables. Neither spelling
implies subscription, mounting, cleanup or validation of its entries by itself.

## 4. The parent owns the connections

A parent can connect a child's event directly to another child's capability. It can also
transform the payload or perform a domain activity before continuing. The children do not need
to discover one another or import their parent's behavior.

Here `button` is only a headless activation source. `label` owns one displayed string. Neither
knows that the other exists, and neither knows about a counter:

```lua
local button = do(on_activate: Function): Table
    return define
        activate = on_activate
    end
end

local label = do(initial: String): Table
    local text = initial
    return define
        display = do(value: String): Unit
            text = value
        end
        current = || -> text
    end
end

local count_label = label "4"
local panel_counting = counter define
    initial = 4
end define
    changed = value -> count_label.display(tostring value)
end
local increment_button = button panel_counting.increment
increment_button.activate
increment_button.activate
assert(panel_counting.current() == 6 and count_label.current() == "6")
assert(counting.current() == 1 and other_counting.current() == 11)
```

The parent wires activation to increment, and change to display. In an actual UI, a native input
source would trigger activation. This example does not choose how native events are delivered.
It also does not require a parent to expose all its children publicly: the parent chooses its
own outward protocol and capabilities.

Opening is available when the block should speak instructions:

```lua
local advance_counter = do(..)
    increment
    return current()
end
assert(advance_counter panel_counting == 7)
assert(count_label.current() == "7")
```

At a wiring site, qualification can be clearer: `button panel_counting.increment` shows exactly
which child owns the operation. Opening is not an obligation to hide meaningful distinctions.

## 5. Compose behavior; do not confuse copying with instantiation

An outward vocabulary can be forwarded by spread and selectively adapted. An explicit entry
names the decision to replace one behavior; there is no implicit event routing:

```lua
local deliveries = {}
local Notify = define
    changed = do(value)
        deliveries[#deliveries + 1] = value
    end
end
local doubled_counting = counter define
    initial = 2
end define ..Notify
    changed = value -> Notify.changed(value * 2)
end
doubled_counting.increment
assert(doubled_counting.current() == 3 and deliveries[1] == 6)
```

The same spread rule applies to capabilities, but it **does not clone captured state**:

```lua
local shared_counting = define ..counting end
shared_counting.increment
assert(counting.current() == 2 and shared_counting.current() == 2)
assert(observations[2] == 2)
assert(other_counting.current() == 11 and #other_observations == 1)
```

`shared_counting` and `counting` reach the same counter. The independent factory call in §3
owns different state. A fresh factory may still intentionally capture a shared document or
notification destination: fresh closures alone do not imply deep isolation.

## 6. Two continuation roles, kept distinct

Continuation passing is a way of connecting ordinary functions, not another component type.
Two uses must remain distinguishable:

| Role | What it receives | When it runs | Responsibility |
|---|---|---|---|
| composition continuation | the child's capabilities | at the declared setup/composition boundary | wire or perform work using those capabilities |
| event continuation | an interaction or payload | when the declared interaction happens, possibly many times | react, forward, or start domain work |

A child can return its capabilities normally, as `counter` does, or supply them to a composition
continuation. Returning a vocabulary does not prevent the parent from wiring continuations into
its children. Use a composition continuation when the enclosing operation has setup and
completion to own, not merely to wrap a return value in another callback.

The eventual API must name or otherwise clearly identify these roles. Do not overload the same
anonymous block to mean either "here are my controls" or "this event happened", inferred from
its parameter shape. The examples' `Notify` stage is specifically for outward events.

These event callbacks are multi-shot: successive activations notify again. They are not
necessarily tail calls or single-use continuations. No CPS spelling alone guarantees one-shot
completion or safe retained state.

## 7. Activities own lifetime and completion

A component's public vocabulary does not establish its resource lifetime. An activity owns
setup and completion; its body uses the capabilities temporarily entrusted to it.

For UI resources, the mounting owner must account for:

- successful setup, partial acquisition failure, normal completion and errors;
- retained callbacks and the state or native resources they capture;
- removing subscriptions and other connections before their targets cease to be usable;
- the promised behavior of a capability used after its lifetime;
- nested ownership and the order in which resources are released.

Returning from a wiring block does not keep a mounted component alive, and returning from a
factory does not dispose it. If a callback escapes setup, its captures need an owner whose
lifetime covers its later calls. A synchronous scoped activity must not hand out a temporary
context and then release it while callbacks still use it. Opening installs no automatic cleanup
or exception unwinding.

**Interaction is not completion.** A button can activate repeatedly; a bounded dialog activity
finishes once. Where terminal alternatives carry different values or require different handling,
represent them with a `oneof` and match them exhaustively. The owner enforces terminality and
performs cleanup; a tagged outcome by itself does neither. Ordinary errors remain broken rules,
not alternate success or cancellation outcomes.

The owner also decides whether component changes are in place, tentative, or committed only on
acceptance. The simple counter is in place. Do not infer transaction semantics from a block or
from continuation passing.

## 8. What the patterns do and do not settle

The agreed model is small:

- component instances can be stateful vocabularies; factories create their owned state;
- inputs, inward capabilities, outward continuations and terminal outcomes have distinct roles;
- parents wire their children's continuations and capabilities locally;
- curried application can stage construction with `define` or `with` arguments;
- activities, not table syntax, own resource lifetimes and completion.

Not every component needs every role. A button can accept one continuation; an editor can offer
an editing vocabulary and report changes; a dialog additionally has a terminal outcome. Do not
impose an empty vocabulary or a universal component record where there is no responsibility.

Still open for the UI framework: the concrete builder and mounting API, whether and where pure
descriptions precede live instances, update scheduling, native callback handling, resource
release mechanics and the BUI integration. These patterns constrain those choices; they do not
pretend the choices have already been made.

### Review checklist

- Can a reader distinguish inputs, commands, queries, events and terminal outcomes?
- Who supplies each vocabulary, and who calls it?
- Does each factory own fresh state where independence is promised?
- Is shared captured state intentional, including after spread?
- Does a composition block have a different contract from an event handler?
- Who owns every retained callback and the lifetime of its targets?
- Are notification order, failure and reentrancy promises explicit?
- Can the behavior and parent wiring be tested without rendering?

> **State belongs to its owner. Capabilities point inward. Continuations point outward.
> Parents connect. Activities complete. `define` names the vocabulary.**
