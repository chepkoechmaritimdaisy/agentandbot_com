defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Continuously fuzzes ClawSpeak and UMP protocols with random binary data generated via `StreamData`.
  """

  use GenServer
  require Logger

  # Default check interval in milliseconds
  @interval 10_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_fuzz()
    {:ok, state}
  end

  @impl true
  def handle_info(:fuzz, state) do
    fuzz_clawspeak()
    fuzz_ump()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp fuzz_clawspeak do
    # Generate random binary data using StreamData
    Enum.each(Enum.take(StreamData.binary(), 100), fn binary ->
      try do
        case GovernanceCore.Protocols.ClawSpeak.decode(binary) do
          {:ok, _, _} -> :ok
          {:error, _} -> :ok
        end
      rescue
        e -> Logger.error("ClawSpeak fuzzer crashed with error: #{inspect(e)} on binary: #{inspect(binary)}")
      catch
        :exit, reason -> Logger.error("ClawSpeak fuzzer exited with reason: #{inspect(reason)} on binary: #{inspect(binary)}")
        kind, value -> Logger.error("ClawSpeak fuzzer caught #{inspect(kind)}: #{inspect(value)} on binary: #{inspect(binary)}")
      end
    end)
  end

  defp fuzz_ump do
    # Generate random binary data using StreamData
    Enum.each(Enum.take(StreamData.binary(), 100), fn binary ->
      try do
        case GovernanceCore.Protocols.UMP.Parser.parse_frame(binary) do
          {:ok, _} -> :ok
          {:error, _} -> :ok
        end
      rescue
        e -> Logger.error("UMP fuzzer crashed with error: #{inspect(e)} on binary: #{inspect(binary)}")
      catch
        :exit, reason -> Logger.error("UMP fuzzer exited with reason: #{inspect(reason)} on binary: #{inspect(binary)}")
        kind, value -> Logger.error("UMP fuzzer caught #{inspect(kind)}: #{inspect(value)} on binary: #{inspect(binary)}")
      end
    end)
  end
end
