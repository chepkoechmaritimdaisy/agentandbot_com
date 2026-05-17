defmodule GovernanceCore.Security.NightlyAudit do
  @moduledoc """
  A GenServer that runs every 24 hours to analyze "Human-in-the-loop"
  agent traffic. Formats findings into the "Decompiler Standard" format,
  filtering for critical keywords like CRITICAL, ERROR, or DENIED.
  """
  use GenServer
  require Logger

  # 24 hours in milliseconds
  @interval 24 * 60 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{last_byte_pos: 0}, name: __MODULE__)
  end

  def init(state) do
    schedule_audit()
    {:ok, state}
  end

  def handle_info(:audit, state) do
    Logger.info("Starting Nightly Security Audit...")
    new_state = perform_audit(state)
    schedule_audit()
    {:noreply, new_state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  defp perform_audit(%{last_byte_pos: last_pos}) do
    log_file = Application.get_env(:governance_core, :audit_log_path)

    if log_file && File.exists?(log_file) do
      stat = File.stat!(log_file)

      # Handle file truncation / log rotation
      read_pos = if stat.size < last_pos, do: 0, else: last_pos

      file = File.open!(log_file, [:read, :binary])
      :file.position(file, read_pos)

      # Process lazily using IO.binstream and Enum.reduce to prevent OOM
      # Gather relevant snippets
      snippets =
        IO.binstream(file, :line)
        |> Enum.reduce([], fn line, acc ->
          if String.contains?(line, ["CRITICAL", "ERROR", "DENIED"]) do
            [line | acc]
          else
            acc
          end
        end)
        |> Enum.reverse()
        |> Enum.join("")

      new_pos = :file.position(file, :cur) |> elem(1)
      File.close(file)

      if snippets != "" do
        report = """
        --- DECOMPILER STANDARD AUDIT ---
        TIMESTAMP: #{DateTime.utc_now() |> DateTime.to_iso8601()}
        SOURCE: HUMAN_IN_THE_LOOP
        TRAFFIC_SNIPPET:
        #{snippets}
        STATUS: ANALYZED
        """
        Logger.warning("Nightly Audit Findings:\n#{report}")
      else
        Logger.info("Nightly Audit completed. No critical issues found.")
      end

      %{last_byte_pos: new_pos}
    else
      Logger.warning("Nightly Audit log file not found or not configured.")
      %{last_byte_pos: last_pos}
    end
  end
end
