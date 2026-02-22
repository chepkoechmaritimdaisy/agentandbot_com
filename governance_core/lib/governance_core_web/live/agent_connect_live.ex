defmodule GovernanceCoreWeb.AgentConnectLive do
  use GovernanceCoreWeb, :live_view

  alias GovernanceCore.Monitoring

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Monitoring.subscribe()
    end

    {:ok,
     assign(socket,
       page_title: "agent/connect · ABL.ONE",
       log_lines: [
         %{text: "[SYS] node=agentandbot.com proto=ABL.ONE/1.0", type: :sys},
         %{text: "[SYS] monitor=active waiting_for_events...", type: :sys}
       ]
     )}
  end

  @impl true
  def handle_info({:new_comment, comment}, socket) do
    type = if comment.source == "ClawHub.ai", do: :clawhub, else: :msg
    new_line = %{text: "[#{String.upcase(to_string(type))}] from=#{comment.author} content=\"#{comment.content}\"", type: type}

    updated_logs = socket.assigns.log_lines ++ [new_line]
    log_lines = if length(updated_logs) > 50, do: Enum.drop(updated_logs, 1), else: updated_logs

    {:noreply, assign(socket, log_lines: log_lines)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <style>
      *, *::before, *::after { box-sizing: border-box; }
      body { background: #0B0F14; margin: 0; font-family: monospace; color: #9AA4B2; }
      .container { max-width: 800px; margin: 0 auto; padding: 20px; }
      .header { border-bottom: 1px solid #1F2937; padding-bottom: 10px; margin-bottom: 20px; }
      .log-box { background: #0A0D11; border: 1px solid #1F2937; padding: 15px; border-radius: 4px; height: 400px; overflow-y: auto; }
      .line { margin-bottom: 5px; font-size: 13px; }
      .sys { color: #64748B; }
      .msg { color: #E6EAF0; }
      .clawhub { color: #F59E0B; font-weight: bold; } /* Orange for ClawHub alerts */
      .footer { margin-top: 20px; font-size: 12px; color: #64748B; }
    </style>

    <div class="container">
      <div class="header">
        <h1>agentandbot.com</h1>
        <small>Real-time Monitoring Console</small>
      </div>

      <div class="log-box" id="logs" phx-update="append">
        <%= for {line, i} <- Enum.with_index(@log_lines) do %>
          <div class={"line #{line.type}"} id={"log-#{i}"}><%= line.text %></div>
        <% end %>
      </div>

      <div class="footer">
        Status: Connected | Protocol: UMP v1.2
      </div>
    </div>
    """
  end
end
