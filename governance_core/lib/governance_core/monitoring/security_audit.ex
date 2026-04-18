defmodule GovernanceCore.Monitoring.SecurityAudit do
  @moduledoc """
  A GenServer that runs nightly to analyze Human-in-the-loop agent traffic.
  Reads from `log/agent_traffic.log` directly using file streams.
  """

  use GenServer
  require Logger

  @interval 24 * 60 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, 0, name: __MODULE__)
  end

  @impl true
  def init(last_byte_pos) do
    schedule_audit()
    {:ok, last_byte_pos}
  end

  @impl true
  def handle_info(:audit, last_byte_pos) do
    new_pos = perform_audit(last_byte_pos)
    schedule_audit()
    {:noreply, new_pos}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  defp perform_audit(last_byte_pos) do
    Logger.info("Starting Nightly Security Audit...")

    log_path = Path.join(:code.priv_dir(:governance_core), "log/agent_traffic.log")

    if File.exists?(log_path) do
      stat = File.stat!(log_path)

      start_pos =
        if stat.size < last_byte_pos do
          0 # File was truncated or rotated
        else
          last_byte_pos
        end

      case File.open(log_path, [:read, :binary]) do
        {:ok, file} ->
          :file.position(file, start_pos)

          # Read lazily to prevent OOM
          IO.binstream(file, :line)
          |> Enum.reduce(0, fn line, acc ->
            # Process line
            # Formatting findings according to 'Decompiler Standard' MVP
            Logger.info("Decompiler Standard Audit: Analyzing traffic -> #{String.trim(line)}")
            acc + byte_size(line)
          end)

          new_pos = start_pos + (File.stat!(log_path).size - start_pos)
          File.close(file)

          Logger.info("Nightly Security Audit completed.")
          new_pos

        {:error, reason} ->
          Logger.error("Failed to open log file: #{inspect(reason)}")
          last_byte_pos
      end
    else
      Logger.warning("Agent traffic log file not found at #{log_path}, skipping audit.")
      last_byte_pos
    end
  end
end
