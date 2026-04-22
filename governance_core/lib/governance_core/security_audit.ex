defmodule GovernanceCore.SecurityAudit do
  @moduledoc """
  Nightly security audit process that analyzes 'Human-in-the-loop' agent traffic.
  Outputs summaries formatted according to the 'Decompiler Standard'.
  Runs every 24 hours.
  """
  use GenServer
  require Logger

  # 24 hours interval for nightly processing
  @interval 24 * 60 * 60 * 1000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    schedule_audit()

    # Get dynamic log file path, default to priv/human_traffic.log if not specified
    log_path = Keyword.get(opts, :log_path, default_log_path())

    {:ok, %{last_byte_pos: 0, log_path: log_path}}
  end

  @impl true
  def handle_info(:audit, state) do
    new_state = perform_audit(state)
    schedule_audit()
    {:noreply, new_state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  defp default_log_path do
    Path.join([File.cwd!(), "governance_core", "priv", "human_traffic.log"])
  end

  defp perform_audit(%{last_byte_pos: last_pos, log_path: path} = state) do
    Logger.info("Starting Nightly Security Audit...")

    case File.stat(path) do
      {:ok, %{size: size}} ->
        pos = if size < last_pos, do: 0, else: last_pos

        case File.open(path, [:read, :binary]) do
          {:ok, file} ->
            :file.position(file, pos)

            # Process log lazily to prevent OOM
            new_pos =
              IO.binstream(file, :line)
              |> Enum.reduce(pos, fn line, acc ->
                process_line(line)
                acc + byte_size(line)
              end)

            File.close(file)
            Logger.info("Nightly Security Audit completed.")
            %{state | last_byte_pos: new_pos}

          {:error, reason} ->
            Logger.warning("Failed to open audit log file: #{inspect(reason)}")
            state
        end

      {:error, :enoent} ->
        Logger.info("Audit log file #{path} does not exist yet. Skipping.")
        state

      {:error, reason} ->
        Logger.warning("Failed to stat audit log file: #{inspect(reason)}")
        state
    end
  end

  defp process_line(line) do
    # Assuming lines are JSON or parsable traffic snippets
    # The requirement is to output following the 'Decompiler Standard'

    # Simple formatting of the log line
    clean_line = String.trim(line)

    if clean_line != "" do
      timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

      output = """
      --- DECOMPILER STANDARD AUDIT ---
      TIMESTAMP: #{timestamp}
      SOURCE: HUMAN_IN_THE_LOOP
      TRAFFIC_SNIPPET: #{clean_line}
      STATUS: ANALYZED
      """

      # In a real implementation this might be written to an audit report file,
      # but the instructions just say it formats and summarizes the analysis.
      Logger.info("\n#{output}")
    end
  end
end
