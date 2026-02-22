defmodule GovernanceCoreWeb.TrafficLive do
  use GovernanceCoreWeb, :live_view

  alias GovernanceCore.Protocols.ClawSpeak

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(GovernanceCore.PubSub, "clawspeak:traffic")
    end

    {:ok, assign(socket, messages: [], page_title: "ClawSpeak Traffic Decompiler")}
  end

  def handle_info({:traffic, raw_binary}, socket) do
    decoded = case ClawSpeak.decode(raw_binary) do
      {:ok, struct, _} -> struct
      _ -> %{error: "Invalid Frame"}
    end

    message = %{
      id: System.unique_integer(),
      timestamp: DateTime.utc_now(),
      raw: Base.encode16(raw_binary),
      decoded: decoded,
      status: :pending # Default status
    }

    {:noreply, stream_insert(socket, :messages, message)}
  end

  def handle_event("approve", %{"id" => id}, socket) do
    # In a real implementation, this would trigger the task execution or release the hold.
    # For now, we just update the UI status.
    # Since streams are append-only mostly, updating a specific item requires re-streaming or using JS.
    # Here we'll just log it.
    id_int = String.to_integer(id)
    Logger.info("Human approved message #{id_int}")

    {:noreply, put_flash(socket, :info, "Message #{id} approved.")}
  end

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl p-4">
      <h1 class="text-2xl font-bold mb-4">ClawSpeak Traffic Decompiler</h1>

      <div id="traffic-stream" phx-update="stream" class="space-y-4">
        <div :for={{id, msg} <- @streams.messages} id={id} class="border p-4 rounded bg-gray-50">
          <div class="flex justify-between">
            <span class="text-sm text-gray-500">{msg.timestamp}</span>
            <span class="font-mono text-xs">{msg.raw}</span>
          </div>

          <div class="mt-2">
            <pre class="bg-gray-800 text-green-400 p-2 rounded text-sm overflow-x-auto">
              {inspect(msg.decoded, pretty: true)}
            </pre>
          </div>

          <div class="mt-2 flex justify-end">
            <%= if msg.decoded[:error] do %>
              <span class="text-red-500 font-bold">Corrupt Frame</span>
            <% else %>
              <button phx-click="approve" phx-value-id={msg.id} class="bg-blue-500 text-white px-3 py-1 rounded hover:bg-blue-600">
                Approve (HitL)
              </button>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
