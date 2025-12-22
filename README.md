# RoboTem Core

An Elixir framework for building event-sourced systems with the Decider Pattern. (Alpha / Early Development)

RoboTem Core provides the architectural foundation for modeling complex domains using Event Sourcing and CQRS. It enforces a clean separation of concerns by splitting business logic into pure decision functions and evolution functions, while a robust runtime manages state, concurrency, and persistence.

    Current Status: This project is in active development. The core pattern and runtime are stable and usable for learning and designing domain models. Production-ready features like adapters, advanced monitoring, and a Dead Letter Queue API are on the roadmap.

Why RoboTem Core?

    Pure Domain Models: Write your business logic as pure, testable functions (decide and evolve). No frameworks, side-effects, or infrastructure concerns in your core domain.

    Event-Sourcing Built-In: Every state change is captured as an immutable event, providing a complete audit log and enabling time-travel debugging.

    Concurrency & Consistency: The DeciderRunner ensures commands for a single aggregate are processed sequentially, guaranteeing state consistency without complex locking.

    Functional Foundation: Built on immutable data and functional principles, leading to more predictable and maintainable code.
    
Core Concepts

The framework is built around the Decider Pattern:

    Command: An intent to change the system (e.g., CreatePerson).

    Decide: A pure function that validates the command against current state and produces a list of Events if valid.

    Event: A factual record of what happened (e.g., PersonCreated). These are persisted.

    Evolve: A pure function that applies an event to the current state to produce a new state.
    
graph LR
    C[Command] --> D{decide/2};
    S[State] --> D;
    D -->|Valid| E[Events];
    D -->|Invalid| Err[Error];
    E --> Persist;
    subgraph "Pure Domain Logic"
        D
        Evolve[evolve/2]
    end
    S --> Evolve;
    E --> Evolve;
    Evolve --> S2[New State];
    
Quick Start: Building a Blink Game

Let's model a simple lottery game where players buy slots. This example shows the complete Decider Pattern.
1. Define the Aggregate

Create lib/blink/game.ex:

defmodule Blink.Game do
  import Pine.DSL # Provides defcommand, defevent helpers

  defstruct [:game_id, :slot_price, :total_slots, slots: %{}, status: :open, total_pot: 0]

  # 1. Define Commands (Intentions)
  defcommand CreateGame, [:game_id, :total_slots, :slot_price]
  defcommand PurchaseSlot, [:client_id, :slot_number, :client_balance]

  # 2. Define Events (Facts)
  defevent GameCreated, [:game_id, :total_slots, :slot_price]
  defevent SlotPurchased, [:game_id, :client_id, :slot_number, :slot_price]

  # 3. Decision Logic (Pure Validation & Event Generation)
  def decide(%CreateGame{total_slots: slots, slot_price: price}, _state)
    when slots >= 3 and price > 0 do
    {:ok, [%GameCreated{game_id: id, total_slots: slots, slot_price: price}]}
  end
  def decide(%CreateGame{}, _state), do: {:error, :invalid_parameters}

  def decide(%PurchaseSlot{client_balance: balance}, %__MODULE__{slot_price: price})
    when balance < price do
    {:error, :insufficient_funds}
  end
  # ... more decision logic

  # 4. Evolution Logic (Pure State Transitions)
  def evolve(state, %GameCreated{game_id: id, total_slots: slots, slot_price: price}) do
    %__MODULE__{state | game_id: id, total_slots: slots, slot_price: price}
  end
  def evolve(state, %SlotPurchased{client_id: cid, slot_number: num}) do
    %__MODULE__{state | slots: Map.put(state.slots, num, cid)}
  end
end

2. Run Commands Through the DeciderRunner

The Pine.DeciderRunner.DefaultRunner manages the aggregate instance.
alias Blink.Game
alias Pine.DeciderRunner.DefaultRunner

# Create a unique ID for the game aggregate
game_id = %Blink.GameID{id: "game_123"}

# Execute a command
command = %Game.CreateGame{game_id: "game_123", total_slots: 10, slot_price: 50}
metadata = %{user_id: "user_1", timestamp: DateTime.utc_now()}

case DefaultRunner.execute_cmd(command, MyApp, game_id, metadata) do
  {:ok, events} ->
    IO.inspect(events, label: "Events Produced")
    # Events are persisted, state is updated
  {:error, reason} ->
    IO.puts("Command failed: #{reason}")
end

3. Query the Current State

# Get the latest state by replaying all events
current_state = DefaultRunner.query(MyApp, game_id)
IO.inspect(current_state.total_pot, label: "Total Pot")

Testing Your Domain

Because the core logic is pure functions, testing is straightforward and requires no framework:

defmodule Blink.GameTest do
  use ExUnit.Case
  alias Blink.Game

  test "purchase slot reduces available slots" do
    # 1. Start from a known state
    state = %Game{game_id: "test", total_slots: 5, slot_price: 100, status: :open}
    # 2. Issue a command
    cmd = %Game.PurchaseSlot{client_id: "alice", slot_number: 1, client_balance: 200}
    # 3. Validate the decision
    assert {:ok, [%Game.SlotPurchased{}]} = Game.decide(cmd, state)
    # 4. Verify the state evolution
    new_state = Game.evolve(state, %Game.SlotPurchased{...})
    assert new_state.slots[1] == "alice"
  end
end
