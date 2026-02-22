defmodule GovernanceCore.Monitoring.CommentMonitor do
  use GenServer

  @topic "comment_updates"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    {:ok, []}
  end

  # Public API

  def broadcast_comment(comment) do
    GenServer.cast(__MODULE__, {:broadcast, comment})
  end

  def get_recent_comments do
    GenServer.call(__MODULE__, :get_recent)
  end

  def subscribe do
    Phoenix.PubSub.subscribe(GovernanceCore.PubSub, @topic)
  end

  # Callbacks

  def handle_cast({:broadcast, comment}, state) do
    # Keep last 50 comments (increased buffer)
    new_state = [comment | state] |> Enum.take(50)
    Phoenix.PubSub.broadcast(GovernanceCore.PubSub, @topic, {:new_comment, comment})
    {:noreply, new_state}
  end

  def handle_call(:get_recent, _from, state) do
    {:reply, state, state}
  end
end
