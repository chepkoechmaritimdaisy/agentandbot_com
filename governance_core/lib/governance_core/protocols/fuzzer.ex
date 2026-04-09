defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  A GenServer that periodically fuzzes the UMP Parser to detect inconsistent pattern matching.
  """
  use GenServer
  require Logger
  import StreamData

  @interval 5_000 # Run fuzzing every 5 seconds

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_fuzz()
    {:ok, state}
  end

  def handle_info(:fuzz, state) do
    perform_fuzz()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  def perform_fuzz do
    # Generate 100 random binary strings of various sizes up to 128 bytes
    fuzz_data_generator = binary(min_length: 0, max_length: 128)

    Enum.each(Enum.take(fuzz_data_generator, 100), fn random_binary ->
      try do
        # Call the parser and just ensure it doesn't crash the GenServer
        _ = GovernanceCore.Protocols.UMP.Parser.parse_frame(random_binary)
      rescue
        e ->
          Logger.error("Fuzzer found exception during UMP parsing: #{inspect(e)}")
      catch
        kind, reason ->
          Logger.error("Fuzzer found unexpected throw/exit during UMP parsing: #{inspect(kind)} #{inspect(reason)}")
      end
    end)
  end
end
