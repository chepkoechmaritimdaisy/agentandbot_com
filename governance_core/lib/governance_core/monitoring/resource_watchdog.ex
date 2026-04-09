defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  A GenServer that monitors Docker container CPU and RAM usage,
  detecting limits and OOM kill risks.
  """
  use GenServer
  require Logger

  # 1 minute in milliseconds
  @interval 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_check()
    {:ok, state}
  end

  def handle_info(:check, state) do
    perform_check()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check, @interval)
  end

  defp perform_check do
    Logger.info("Starting ResourceWatchdog check...")

    try do
      {output, 0} = System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}}: {{.CPUPerc}} CPU, {{.MemPerc}} RAM"])

      output
      |> String.split("\n", trim: true)
      |> Enum.each(&process_stat/1)

    rescue
      e in ErlangError -> Logger.warning("docker command not found or failed: #{inspect(e)}")
    end

    Logger.info("ResourceWatchdog check completed.")
  end

  defp process_stat(stat) do
    # Expected format: "name: XX.XX% CPU, YY.YY% RAM"
    # Example: "agent_node: 12.5% CPU, 85.0% RAM"
    Logger.info("Container Stat: #{stat}")

    case Regex.run(~r/RAM\s*:\s*([\d\.]+)%/, stat) do
      [_, ram_str] ->
        case Float.parse(ram_str) do
          {ram, _} when ram > 90.0 ->
            Logger.warning("Container near OOM Kill limit! RAM Usage: #{ram}% - #{stat}")
          _ ->
            :ok
        end
      _ ->
        # Try another format in case the formatting changed
        case Regex.run(~r/([\d\.]+)%\s*RAM/, stat) do
          [_, ram_str] ->
             case Float.parse(ram_str) do
               {ram, _} when ram > 90.0 ->
                 Logger.warning("Container near OOM Kill limit! RAM Usage: #{ram}% - #{stat}")
               _ ->
                 :ok
             end
          _ ->
            :ok
        end
    end
  end
end
